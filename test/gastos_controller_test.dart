import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:exploraec/controllers/auth_controller.dart';
import 'package:exploraec/controllers/gastos_controller.dart';
import 'package:exploraec/controllers/places_controller.dart' show EstadoCarga;
import 'package:exploraec/repositories/gastos_repository.dart';
import 'package:exploraec/services/api_client.dart';
import 'package:exploraec/services/gastos_api_service.dart';
import 'package:exploraec/services/secure_token_storage.dart';
import 'package:exploraec/services/settings_service.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart' hide Response;
import 'package:hive/hive.dart';

import 'helpers/servidor_gastos_falso.dart';

// Datos sintéticos: las pruebas los comparan, nunca los imprimen.
const _correo = 'a@b.com';
const _clave = 'clave-1234';

const _dosGastos = [
  {'id': 1, 'descripcion': 'Almuerzo', 'monto': 6.5, 'categoria': 'comida', 'fecha': '2026-10-05'},
  {'id': 2, 'descripcion': 'Taxi', 'monto': 3, 'categoria': 'transporte', 'fecha': '2026-10-05'},
];

/// 45 gastos sintéticos (ids 1..45): tres páginas de 20, 20 y 5.
final _cuarentaYCinco = List.generate(
  45,
  (i) => <String, dynamic>{'id': i + 1, 'descripcion': 'Gasto ${i + 1}', 'monto': 1 + i, 'categoria': 'comida', 'fecha': '2026-10-18'},
);

/// Servidor con un único usuario (`a@b.com`, id 1).
ServidorGastosFalso _servidor({List<Map<String, dynamic>> gastos = const [], int? total}) =>
    ServidorGastosFalso({
      _correo: UsuarioFalso(id: 1, password: _clave, gastos: List.of(gastos), total: total),
    });

/// Almacenamiento seguro que falla al borrar (para probar que no se oculta).
class _AlmacenQueFallaAlBorrar extends SecureTokenStorage {
  @override
  Future<void> borrar() async => throw const FileSystemException('almacenamiento no disponible');
}

/// Almacenamiento seguro (simulado) que cuenta cuántas veces se borró.
class _AlmacenQueCuentaBorrados extends SecureTokenStorage {
  int borrados = 0;
  @override
  Future<void> borrar() {
    borrados++;
    return super.borrar();
  }
}

/// Repositorio cuya caja no se puede borrar del disco.
class _RepositorioQueFallaAlVaciar extends GastosRepository {
  _RepositorioQueFallaAlVaciar(super.api);
  @override
  Future<bool> vaciar() async {
    await super.vaciar();
    throw const FileSystemException('disco no disponible');
  }
}

void main() {
  // Carpeta temporal propia de este archivo: Hive nunca escribe fuera de ella.
  late Directory carpetaHive;
  late ServidorGastosFalso servidor;
  late AuthController auth;

  setUpAll(() {
    carpetaHive = Directory.systemTemp.createTempSync('exploraec_hive_gastos_');
    Hive.init(carpetaHive.path);
    Get.isLogEnable = false;
  });
  setUp(() async {
    Get.reset();
    Get.testMode = true;
    FlutterSecureStorage.setMockInitialValues({});
    // Cierra y borra las cajas abiertas (todas viven en `carpetaHive`):
    // cada prueba parte sin ninguna caja.
    await Hive.deleteFromDisk();
  });
  tearDown(Get.reset);
  tearDownAll(() async {
    await Hive.close();
    if (carpetaHive.existsSync()) carpetaHive.deleteSync(recursive: true);
  });

  /// Registra lo mismo que la app (`main()` + `PlacesBinding`) sobre [s].
  void montar(ServidorGastosFalso s, {SecureTokenStorage? almacen, GastosRepository Function()? repositorio}) {
    servidor = s;
    Get.put<ApiClient>(ApiClient(dio: s.crearDio()), permanent: true);
    auth = Get.put<AuthController>(AuthController(almacen: almacen), permanent: true);
    Get.lazyPut<GastosController>(() => GastosController(repositorio: repositorio?.call()));
  }

  /// Sesión controlada: el controller de Gastos ya existe (pestaña abierta),
  /// se inicia sesión y se espera la carga inicial.
  Future<GastosController> entrar(ServidorGastosFalso s,
      {String correo = _correo, String clave = _clave}) async {
    if (!Get.isRegistered<AuthController>()) montar(s);
    final g = Get.find<GastosController>();
    await auth.iniciarSesion(correo, clave);
    await g.cargaInicial;
    return g;
  }

  // ---- Sesión 6 (adaptadas a dio y AuthController) ----

  test('Paso 3 — usuario nuevo: registro -> login -> lista vacía', () async {
    montar(_servidor());
    final g = Get.find<GastosController>();
    await auth.registrar('nuevo@b.com', _clave);
    await g.cargaInicial;
    expect(auth.estaAutenticado, isTrue);
    expect(g.estado.value, EstadoCarga.exito);
    expect(g.gastos, isEmpty);
  });

  test('éxito: carga gastos y total desde X-Total-Count (monto entero o decimal), sin banner', () async {
    final g = await entrar(_servidor(gastos: _dosGastos));
    expect(g.gastos.length, 2);
    expect(g.totalEnServidor.value, 2);
    expect(g.gastos[1].monto, 3.0);
    expect(g.desdeCache.value, isFalse);
  });

  test('Paso 3 — correo existente (400): muestra el detail del servidor y no entra', () async {
    montar(_servidor());
    await auth.registrar(_correo, _clave);
    expect(auth.estaAutenticado, isFalse);
    expect(auth.mensajeError.value, 'El email $_correo ya está registrado');
  });

  test('Paso 3 — 422 al registrar: mensaje legible con el campo, sin sesión', () async {
    montar(_servidor());
    await auth.registrar('nuevo@b.com', 'abc');
    expect(auth.estaAutenticado, isFalse);
    expect(auth.mensajeError.value, startsWith('Datos inválidos — password:'));
  });

  test('sin conexión y sin copia: error legible y la sesión no se pierde', () async {
    final s = _servidor()..sinRedAlListar = true;
    final g = await entrar(s);
    expect(g.estado.value, EstadoCarga.error);
    expect(g.mensajeError.value, startsWith('No hay conexión con el servidor'));
    expect(auth.estaAutenticado, isTrue);
    expect(g.desdeCache.value, isFalse);
  });

  test('401 al listar: cierra la sesión, borra token y copia, sin usar la copia', () async {
    final g = await entrar(_servidor(gastos: _dosGastos));
    servidor.falloListar = 401;
    await g.cargarGastos();
    expect(auth.estaAutenticado, isFalse);
    await auth.cierrePorCaducidad;
    expect(g.desdeCache.value, isFalse);
    expect(g.gastos, isEmpty);
    expect(g.estado.value, EstadoCarga.exito, reason: 'El error de la sesión cerrada no se muestra');
    expect(await SecureTokenStorage().leer(), isNull);
    expect(await Hive.boxExists('gastos_1'), isFalse);
    expect(auth.avisoSesion.value, 'Tu sesión caducó, inicia sesión de nuevo.');
  });

  test('Paso 7 — 401 al listar: vuelve a «sin sesión» y explica por qué', () async {
    final g = await entrar(_servidor(gastos: _dosGastos));
    servidor.falloListar = 401;
    await g.cargarGastos();
    expect(auth.estaAutenticado, isFalse);
    await auth.cierrePorCaducidad; // el interceptor no espera el cierre
    expect(auth.avisoSesion.value, 'Tu sesión caducó, inicia sesión de nuevo.');
  });

  test('5xx sin copia: mensaje genérico', () async {
    final s = _servidor()..falloListar = 503;
    final g = await entrar(s);
    expect(g.estado.value, EstadoCarga.error);
    expect(g.desdeCache.value, isFalse);
    expect(g.mensajeError.value, 'El servidor tuvo un problema. Inténtalo más tarde.');
  });

  group('Orden y formato de las peticiones', () {
    test('login -> perfil -> categorías -> listado, en ese orden y desde skip 0', () async {
      await entrar(_servidor(gastos: _dosGastos));
      expect(servidor.rutas,
          ['POST /usuarios/token', 'GET /usuarios/me', 'GET /gastos/categorias', 'GET /gastos/']);
      expect(servidor.consultasDeListado, [
        {'skip': '0', 'limit': '20'}
      ]);
    });

    test('login en formulario y sin token; perfil y listado con Bearer', () async {
      await entrar(_servidor());
      final login = servidor.peticiones.singleWhere((p) => p.ruta == '/usuarios/token');
      final perfil = servidor.peticiones.singleWhere((p) => p.ruta == '/usuarios/me');
      final listado = servidor.peticiones.singleWhere((p) => p.ruta == '/gastos/');

      expect(login.tipoContenido, contains('application/x-www-form-urlencoded'));
      expect(Uri.splitQueryString(login.cuerpo), {'username': _correo, 'password': _clave});
      expect(login.cuerpo.trimLeft().startsWith('{'), isFalse, reason: 'No debe ir en JSON');
      expect(login.autorizacion, isNull);

      // Se compara sin imprimir el token: solo un booleano en el mensaje.
      final esperado = 'Bearer ${servidor.usuarios[_correo]!.token}';
      expect(perfil.autorizacion == esperado, isTrue);
      expect(listado.autorizacion == esperado, isTrue);
    });

    test('Paso 3 — el registro va en JSON y sin token', () async {
      montar(_servidor());
      await auth.registrar('nuevo@b.com', _clave);
      final registro = servidor.peticiones.first;
      expect('$registro', 'POST /usuarios/');
      expect(registro.tipoContenido, contains('application/json'));
      expect(registro.cuerpo, '{"email":"nuevo@b.com","password":"$_clave"}');
      expect(registro.autorizacion, isNull);
    });

    test('Paso 3 — correo existente (400): no inicia sesión ni pide nada más', () async {
      montar(_servidor());
      await auth.registrar(_correo, _clave);
      expect(servidor.rutas, ['POST /usuarios/']);
      expect(auth.mensajeError.value, isNotEmpty);
    });
  });

  group('Errores que impiden continuar', () {
    test('Paso 3 — 5xx al registrar: no intenta el login ni el listado', () async {
      montar(_servidor()..falloRegistro = 500);
      await auth.registrar('nuevo@b.com', _clave);
      expect(servidor.rutas, ['POST /usuarios/']);
      expect(auth.estaAutenticado, isFalse);
      expect(auth.mensajeError.value, 'El servidor tuvo un problema. Inténtalo más tarde.');
      expect(auth.cargando.value, isFalse);
    });

    test('credenciales incorrectas (401 en login): no lista y sigue sin sesión', () async {
      final g = await entrar(_servidor(), clave: 'otra-clave-1');
      expect(servidor.rutas, ['POST /usuarios/token']);
      expect(auth.estaAutenticado, isFalse);
      expect(auth.mensajeError.value, 'Email o contraseña incorrectos');
      expect(auth.cargando.value, isFalse);
      expect(g.gastos, isEmpty);
    });

    test('sin conexión al entrar: mensaje legible y cargando vuelve a false', () async {
      await entrar(_servidor()..sinRed = true);
      expect(servidor.peticiones, hasLength(1));
      expect(auth.estaAutenticado, isFalse);
      expect(auth.mensajeError.value, startsWith('No hay conexión con el servidor'));
      expect(auth.cargando.value, isFalse);
    });
  });

  group('cargando (antes «autenticando»)', () {
    test('es true mientras el login espera y false al terminar', () async {
      final s = _servidor()..retenerLogin = Completer<void>();
      montar(s);
      final flujo = auth.iniciarSesion(_correo, _clave);
      // El login queda en espera: el flujo sigue en marcha.
      await Future<void>.delayed(Duration.zero);
      expect(auth.cargando.value, isTrue);
      expect(auth.estaAutenticado, isFalse);

      s.retenerLogin!.complete();
      await flujo;
      expect(auth.cargando.value, isFalse);
      expect(auth.estaAutenticado, isTrue);
    });

    test('vuelve a false tras cada tipo de error y permite reintentar', () async {
      final s = _servidor();
      montar(s);
      for (final provocar in <void Function()>[
        () => s.sinRed = true,
        () => s.falloLogin = 503,
        () => s.falloLogin = 401,
      ]) {
        s
          ..sinRed = false
          ..falloLogin = null;
        provocar();
        await auth.iniciarSesion(_correo, _clave);
        expect(auth.cargando.value, isFalse);
        expect(auth.estaAutenticado, isFalse);
        expect(auth.mensajeError.value, isNotEmpty);
      }
      // Un reintento correcto limpia el mensaje y entra.
      s
        ..sinRed = false
        ..falloLogin = null;
      await auth.iniciarSesion(_correo, _clave);
      expect(auth.estaAutenticado, isTrue);
      expect(auth.mensajeError.value, isEmpty);
    });
  });

  group('Listado', () {
    test('lista vacía: éxito sin gastos y total 0', () async {
      final g = await entrar(_servidor());
      expect(g.estado.value, EstadoCarga.exito);
      expect(g.gastos, isEmpty);
      expect(g.totalEnServidor.value, 0);
      expect(g.hayMas, isFalse);
    });

    test('total del servidor (X-Total-Count) aunque llegue una sola página', () async {
      final g = await entrar(_servidor(gastos: _dosGastos, total: 45));
      expect(g.gastos.map((x) => x.descripcion).toList(), ['Almuerzo', 'Taxi']);
      expect(g.totalEnServidor.value, 45);
      expect(g.hayMas, isTrue);
    });

    test('un fallo de recarga con copia muestra los gastos guardados', () async {
      final g = await entrar(_servidor(gastos: _dosGastos));
      expect(g.gastos, hasLength(2));

      // Sin red, tiempo agotado o 5xx caen a la copia (éxito con `desdeCache`).
      for (final provocar in <void Function()>[
        () => servidor.sinRedAlListar = true,
        () => servidor.timeoutAlListar = true,
        () => servidor.falloListar = 503,
      ]) {
        servidor
          ..sinRedAlListar = false
          ..timeoutAlListar = false
          ..falloListar = null;
        provocar();
        await g.cargarGastos();
        expect(g.estado.value, EstadoCarga.exito);
        expect(g.desdeCache.value, isTrue);
        expect(g.gastos.map((x) => x.descripcion).toList(), ['Almuerzo', 'Taxi']);
        expect(g.totalEnServidor.value, 2);
        expect(auth.estaAutenticado, isTrue);
      }

      // Al recuperarse, vuelve a los datos del servidor y el aviso se apaga.
      servidor.falloListar = null;
      await g.cargarGastos();
      expect(g.estado.value, EstadoCarga.exito);
      expect(g.desdeCache.value, isFalse);
    });

    test('401 al recargar: la lista de la sesión cerrada no queda a la vista', () async {
      final g = await entrar(_servidor(gastos: _dosGastos));
      servidor.falloListar = 401;
      await g.cargarGastos();
      await auth.cierrePorCaducidad;
      expect(auth.estaAutenticado, isFalse);
      expect(g.desdeCache.value, isFalse);
      expect(g.gastos, isEmpty);
      expect(g.mensajeError.value, isEmpty);
    });
  });

  group('Caja de Hive por usuario', () {
    test('al entrar se abre la caja gastos_<id> con el id que obtuvo AuthController', () async {
      final g = await entrar(_servidor(gastos: _dosGastos));
      expect(auth.usuario.value!.id, 1);
      expect(g.estado.value, EstadoCarga.exito);
      expect(Hive.isBoxOpen('gastos_1'), isTrue);
      expect(await Hive.boxExists('gastos_1'), isTrue);
      // `/usuarios/me` se pide una sola vez (el repositorio no lo repite).
      expect(servidor.rutas.where((r) => r == 'GET /usuarios/me'), hasLength(1));
    });

    test('el token no se guarda en Hive (sí en el almacenamiento seguro)', () async {
      await entrar(_servidor(gastos: _dosGastos));
      final token = servidor.usuarios[_correo]!.token;
      final caja = Hive.box('gastos_1');
      final contenido = [...caja.keys, ...caja.values].map((x) => '$x').join(' ');
      // Solo booleanos en el mensaje: el token nunca se imprime.
      expect(contenido.contains(token), isFalse);
      expect(caja.keys.any((k) => '$k'.toLowerCase().contains('token')), isFalse);
      expect(await SecureTokenStorage().leer() == token, isTrue);
    });

    test('perfil inaccesible (5xx en /usuarios/me): no entra, no lista y no deja el token', () async {
      final s = _servidor()..falloPerfil = 503;
      final g = await entrar(s);
      expect(s.rutas, ['POST /usuarios/token', 'GET /usuarios/me']);
      expect(auth.estaAutenticado, isFalse);
      expect(auth.mensajeError.value, 'El servidor tuvo un problema. Inténtalo más tarde.');
      expect(auth.cargando.value, isFalse);
      expect(Get.find<ApiClient>().token, isNull);
      expect(await SecureTokenStorage().leer(), isNull);
      expect(g.gastos, isEmpty);
      expect(Hive.isBoxOpen('gastos_1'), isFalse);
    });
  });

  group('Paginación y copia local', () {
    test('respaldo tras cargar varias páginas: copia de 40 de 45, sin «Cargar más»', () async {
      final g = await entrar(_servidor(gastos: _cuarentaYCinco)..paginar = true);
      expect(g.gastos, hasLength(20));
      expect(g.totalEnServidor.value, 45);
      expect(g.hayMas, isTrue);

      await g.cargarMas();
      expect(g.gastos.map((x) => x.id).toList(), List.generate(40, (i) => i + 1));
      expect(servidor.consultasDeListado, [
        {'skip': '0', 'limit': '20'},
        {'skip': '20', 'limit': '20'},
      ]);

      // La copia en Hive es exactamente lo que está a la vista, con el total.
      final caja = Hive.box('gastos_1');
      expect((caja.get('gastos') as List), hasLength(40));
      expect(caja.get('total'), 45);
      expect(caja.get('sincronizado'), isA<String>());

      servidor.sinRed = true;
      await g.cargarGastos();
      expect(g.estado.value, EstadoCarga.exito);
      expect(g.desdeCache.value, isTrue);
      expect(g.gastos.map((x) => x.id).toList(), List.generate(40, (i) => i + 1));
      expect(g.totalEnServidor.value, 45, reason: 'El total conocido se conserva como metadato');
      expect(g.hayMas, isFalse, reason: 'Con la copia a la vista no se ofrece «Cargar más»');

      // Y aunque se llame, no pide nada ni cambia la lista.
      final antes = servidor.peticiones.length;
      await g.cargarMas();
      expect(servidor.peticiones, hasLength(antes));
      expect(g.gastos, hasLength(40));
    });

    test('una recarga exitosa reemplaza la copia anterior', () async {
      final g = await entrar(_servidor(gastos: _cuarentaYCinco)..paginar = true);
      await g.cargarMas();
      expect(g.gastos, hasLength(40));

      // El servidor ahora tiene solo 2 gastos: la copia de 40 desaparece.
      servidor.usuarios[_correo]!.gastos = List.of(_dosGastos);
      await g.cargarGastos();
      expect(g.gastos.map((x) => x.descripcion).toList(), ['Almuerzo', 'Taxi']);
      expect(g.totalEnServidor.value, 2);
      expect(g.desdeCache.value, isFalse);

      servidor.sinRed = true;
      await g.cargarGastos();
      expect(g.desdeCache.value, isTrue);
      expect(g.gastos.map((x) => x.descripcion).toList(), ['Almuerzo', 'Taxi']);
      expect(g.totalEnServidor.value, 2);
    });

    test('un fallo de página adicional conserva lo mostrado, avisa y no duplica', () async {
      final g = await entrar(_servidor(gastos: _cuarentaYCinco)..paginar = true);
      final primeraPagina = List.generate(20, (i) => i + 1);
      final antes = servidor.peticiones.length;

      for (final provocar in <void Function()>[
        () => servidor.sinRedAlListar = true,
        () => servidor.timeoutAlListar = true,
        () => servidor.falloListar = 503,
      ]) {
        servidor
          ..sinRedAlListar = false
          ..timeoutAlListar = false
          ..falloListar = null;
        provocar();
        await g.cargarMas();
        expect(g.gastos.map((x) => x.id).toList(), primeraPagina);
        expect(g.estado.value, EstadoCarga.exito);
        expect(g.desdeCache.value, isFalse, reason: 'No se presenta la copia como página siguiente');
        expect(g.totalEnServidor.value, 45);
        expect(g.hayMas, isTrue);
        expect(g.mensajeCargarMas.value, isNotEmpty);
        expect(g.cargandoMas.value, isFalse);
      }
      // Cada intento pidió la página siguiente (skip 20), nunca la primera.
      final intentos = servidor.consultasDeListado.sublist(1);
      expect(servidor.peticiones.length - antes, 3);
      expect(intentos.map((q) => q['skip']).toSet(), {'20'});

      // El reintento correcto suma la página sin repetir y limpia el aviso.
      servidor.falloListar = null;
      await g.cargarMas();
      expect(g.gastos.map((x) => x.id).toList(), List.generate(40, (i) => i + 1));
      expect(g.mensajeCargarMas.value, isEmpty);

      // La copia guardada también quedó con 40, sin duplicados.
      servidor.sinRed = true;
      await g.cargarGastos();
      final ids = g.gastos.map((x) => x.id).toList();
      expect(ids, hasLength(40));
      expect(ids.toSet(), hasLength(40));
    });

    test('una página que repite un gasto ya mostrado no lo duplica', () async {
      final g = await entrar(_servidor(gastos: _cuarentaYCinco)..paginar = true);
      // Llega 20..39: el 20 ya estaba a la vista.
      servidor.solapar = 1;
      await g.cargarMas();
      final ids = g.gastos.map((x) => x.id).toList();
      expect(ids, List.generate(39, (i) => i + 1));
      expect(ids.toSet(), hasLength(ids.length));
      expect(g.hayMas, isTrue);
    });

    test('una copia de lista vacía también es una copia válida', () async {
      final g = await entrar(_servidor());
      expect(await Hive.boxExists('gastos_1'), isTrue);
      for (final provocar in <void Function()>[
        () => servidor.sinRedAlListar = true,
        () => servidor.falloListar = 503,
      ]) {
        servidor
          ..sinRedAlListar = false
          ..falloListar = null;
        provocar();
        await g.cargarGastos();
        expect(g.estado.value, EstadoCarga.exito);
        expect(g.desdeCache.value, isTrue);
        expect(g.gastos, isEmpty);
        expect(g.totalEnServidor.value, 0);
        expect(g.hayMas, isFalse);
      }
    });

    test('400/403/404 al recargar no usan la copia', () async {
      final g = await entrar(_servidor(gastos: _dosGastos));
      for (final codigo in [400, 403, 404]) {
        servidor.falloListar = codigo;
        await g.cargarGastos();
        expect(g.estado.value, EstadoCarga.error, reason: 'HTTP $codigo');
        expect(g.desdeCache.value, isFalse, reason: 'HTTP $codigo');
        expect(g.mensajeError.value, isNotEmpty);
        expect(auth.estaAutenticado, isTrue);
      }
    });

    test('tras mostrar la copia, un 401 da error sin usarla', () async {
      final g = await entrar(_servidor(gastos: _dosGastos));
      servidor.sinRed = true;
      await g.cargarGastos();
      expect(g.desdeCache.value, isTrue);
      servidor
        ..sinRed = false
        ..falloListar = 401;
      await g.cargarGastos();
      await auth.cierrePorCaducidad;
      expect(auth.estaAutenticado, isFalse);
      expect(g.desdeCache.value, isFalse);
      expect(g.gastos, isEmpty);
      expect(await Hive.boxExists('gastos_1'), isFalse, reason: 'Ni la copia queda en el disco');
    });
  });

  // ---- Pruebas del starter de la Sesión 7, adaptadas ----

  test('Sesión 7 — 5xx sin nada en caché: error legible', () async {
    final g = await entrar(_servidor()..falloListar = 503);
    expect(g.estado.value, EstadoCarga.error);
    expect(g.mensajeError.value, 'El servidor tuvo un problema. Inténtalo más tarde.');
  });

  test('Sesión 7 — sin conexión con caché: muestra lo guardado y marca desdeCache', () async {
    final g = await entrar(_servidor(gastos: _dosGastos));
    servidor.sinRed = true;
    await g.cargarGastos();
    expect(g.estado.value, EstadoCarga.exito);
    expect(g.desdeCache.value, isTrue);
    expect(g.gastos.length, 2);
    expect(g.ultimaSincronizacion, isNot('desconocida'));
  });

  test('Sesión 7 — 5xx con caché: también cae a la caché', () async {
    final g = await entrar(_servidor(gastos: _dosGastos));
    servidor.falloListar = 503;
    await g.cargarGastos();
    expect(g.desdeCache.value, isTrue);
    expect(g.gastos.length, 2);
  });

  test('Sesión 7 — al volver el servidor, el banner desaparece', () async {
    final g = await entrar(_servidor(gastos: _dosGastos));
    servidor.sinRed = true;
    await g.cargarGastos();
    servidor.sinRed = false;
    await g.cargarGastos();
    expect(g.desdeCache.value, isFalse);
  });

  test('Sesión 7 — un 401 NO usa la caché', () async {
    final g = await entrar(_servidor(gastos: _dosGastos));
    servidor.falloListar = 401;
    await g.cargarGastos();
    await auth.cierrePorCaducidad;
    expect(g.desdeCache.value, isFalse);
    expect(g.gastos, isEmpty);
    expect(auth.avisoSesion.value, startsWith('Tu sesión caducó'));
  });

  test('Sesión 7 — cerrar sesión borra la caja del usuario', () async {
    await entrar(_servidor(gastos: _dosGastos));
    expect(await Hive.boxExists('gastos_1'), isTrue);
    expect(await auth.cerrarSesion(), isTrue);
    expect(await Hive.boxExists('gastos_1'), isFalse);
    expect(auth.estaAutenticado, isFalse);
  });

  // ---- Cerrar sesión (Sesión 7, Paso 5 → AuthController en la Sesión 8) ----

  group('Cerrar sesión', () {
    File archivoCaja(String nombre) => File('${carpetaHive.path}${Platform.pathSeparator}$nombre.hive');

    test('borra gastos_<id> del disco, conserva favoritos y limpia el estado', () async {
      final favoritos = await Hive.openBox<Map>('favoritos');
      await favoritos.put('lugar-1', {'id': 'lugar-1', 'nombre': 'Mitad del Mundo'});

      final g = await entrar(_servidor(gastos: _cuarentaYCinco)..paginar = true);
      await g.cargarMas();
      // Se deja también un aviso de «Cargar más» pendiente.
      servidor.sinRedAlListar = true;
      await g.cargarMas();
      expect(g.mensajeCargarMas.value, isNotEmpty);
      expect(g.gastos, hasLength(40));
      expect(archivoCaja('gastos_1').existsSync(), isTrue);

      expect(await auth.cerrarSesion(), isTrue);

      expect(Hive.isBoxOpen('gastos_1'), isFalse);
      expect(archivoCaja('gastos_1').existsSync(), isFalse);
      expect(await Hive.boxExists('gastos_1'), isFalse);
      expect(Hive.isBoxOpen('favoritos'), isTrue);
      expect(archivoCaja('favoritos').existsSync(), isTrue);
      expect(favoritos.get('lugar-1')?['nombre'], 'Mitad del Mundo');
      expect(auth.estaAutenticado, isFalse);
      expect(auth.avisoSesion.value, isEmpty);
      expect(g.gastos, isEmpty);
      expect(g.totalEnServidor.value, 0);
      expect(g.desdeCache.value, isFalse);
      expect(g.cargandoMas.value, isFalse);
      expect(g.mensajeCargarMas.value, isEmpty);
      expect(g.estado.value, EstadoCarga.exito);
      expect(g.hayMas, isFalse);
      expect(g.ultimaSincronizacion, 'desconocida');
      expect(await SecureTokenStorage().leer(), isNull);
      expect(Get.find<ApiClient>().token, isNull);
    });

    test('salir con la copia local a la vista también la borra y quita el aviso', () async {
      final g = await entrar(_servidor(gastos: _dosGastos));
      servidor.sinRed = true;
      await g.cargarGastos();
      expect(g.desdeCache.value, isTrue);

      await auth.cerrarSesion();
      expect(g.desdeCache.value, isFalse);
      expect(g.gastos, isEmpty);
      expect(await Hive.boxExists('gastos_1'), isFalse);
    });

    test('cerrar sesión conserva el idioma guardado (caja ajustes, Sesión 7 Paso 6)', () async {
      final ajustes = await Hive.openBox('ajustes');
      await ajustes.put('idioma', 'en');
      await entrar(_servidor(gastos: _dosGastos));

      await auth.cerrarSesion();
      expect(await Hive.boxExists('gastos_1'), isFalse);
      expect(Hive.isBoxOpen('ajustes'), isTrue);
      expect(archivoCaja('ajustes').existsSync(), isTrue);
      expect(ajustes.get('idioma'), 'en');
    });

    test('después de salir, el token ya no se envía', () async {
      final g = await entrar(_servidor(gastos: _dosGastos));
      await auth.cerrarSesion();
      final antes = servidor.peticiones.length;
      // Sin sesión, recargar no pide nada.
      await g.cargarGastos();
      expect(servidor.peticiones, hasLength(antes));
      // Y una petición directa ya no lleva `Authorization`.
      await expectLater(Get.find<ApiClient>().get('/usuarios/me'), throwsA(isA<ApiException>()));
      expect(servidor.peticiones.last.autorizacion, isNull);
    });

    test('no crea GastosController si nunca se abrió la pestaña Gastos', () async {
      montar(_servidor(gastos: _dosGastos));
      await auth.iniciarSesion(_correo, _clave);
      expect(Get.isPrepared<GastosController>(), isTrue);
      final antes = servidor.peticiones.length;

      expect(await auth.cerrarSesion(), isTrue);
      expect(Get.isPrepared<GastosController>(), isTrue, reason: 'Sigue sin crearse');
      expect(servidor.peticiones, hasLength(antes), reason: 'Cerrar sesión no dispara cargas');
      expect(await Hive.boxExists('gastos_1'), isFalse);
    });

    test('dos cierres a la vez hacen un solo borrado y ambos terminan bien', () async {
      await entrar(_servidor(gastos: _dosGastos));
      final resultados = await Future.wait([auth.cerrarSesion(), auth.cerrarSesion()]);
      expect(resultados, [isTrue, isTrue]);
      expect(await Hive.boxExists('gastos_1'), isFalse);
      expect(auth.avisoSesion.value, isEmpty);
    });

    test('si no se puede borrar el token, se intenta igual la caché y se avisa', () async {
      montar(_servidor(gastos: _dosGastos), almacen: _AlmacenQueFallaAlBorrar());
      final g = await entrar(servidor);

      expect(await auth.cerrarSesion(), isFalse);
      expect(auth.estaAutenticado, isFalse);
      expect(Get.find<ApiClient>().token, isNull);
      expect(g.gastos, isEmpty);
      expect(await Hive.boxExists('gastos_1'), isFalse, reason: 'La caché se borró igual');
      expect(auth.avisoSesion.value, contains('el token guardado'));
      expect(auth.avisoSesion.value.contains('tus gastos guardados'), isFalse,
          reason: 'No se informa un fallo que no ocurrió');
    });

    test('si no se puede borrar la caché, la memoria queda limpia, el token se borra y se avisa', () async {
      montar(_servidor(gastos: _dosGastos),
          repositorio: () => _RepositorioQueFallaAlVaciar(GastosApiService(Get.find<ApiClient>())));
      final g = await entrar(servidor);
      expect(g.gastos, hasLength(2));

      expect(await auth.cerrarSesion(), isFalse);
      expect(auth.estaAutenticado, isFalse);
      expect(g.gastos, isEmpty);
      expect(g.totalEnServidor.value, 0);
      expect(await SecureTokenStorage().leer(), isNull, reason: 'El token se borró igual');
      expect(auth.avisoSesion.value, contains('tus gastos guardados'));
      expect(auth.avisoSesion.value.contains('el token guardado'), isFalse);
    });

    group('usuario A -> cerrar sesión -> usuario B', () {
      final gastosA = List.generate(
        20,
        (i) => <String, dynamic>{'id': 100 + i, 'descripcion': 'Gasto de A ${i + 1}', 'monto': 10 + i, 'categoria': 'comida', 'fecha': '2026-10-18'},
      );
      ServidorGastosFalso dosUsuarios() => ServidorGastosFalso({
            'a@ejemplo.com': UsuarioFalso(id: 7, password: _clave, gastos: List.of(gastosA), total: 45),
            'b@ejemplo.com': UsuarioFalso(id: 8, password: _clave),
          });

      Future<GastosController> aYLuegoB({bool bSinRed = false}) async {
        final g = await entrar(dosUsuarios(), correo: 'a@ejemplo.com');
        expect(g.gastos, hasLength(20));
        expect(g.totalEnServidor.value, 45);
        expect(await Hive.boxExists('gastos_7'), isTrue);

        await auth.cerrarSesion();
        expect(await Hive.boxExists('gastos_7'), isFalse);

        servidor.sinRedAlListar = bSinRed;
        await auth.iniciarSesion('b@ejemplo.com', _clave);
        await g.cargaInicial;
        return g;
      }

      test('B ve solo lo suyo: lista vacía, total 0 y su propia caja', () async {
        final g = await aYLuegoB();
        expect(auth.usuario.value!.id, 8);
        expect(g.gastos, isEmpty);
        expect(g.totalEnServidor.value, 0);
        expect(g.desdeCache.value, isFalse);
        expect(g.hayMas, isFalse);
        expect(await Hive.boxExists('gastos_7'), isFalse);
        expect(await Hive.boxExists('gastos_8'), isTrue);
        final cajaB = Hive.box('gastos_8');
        expect(cajaB.get('gastos'), isEmpty);
        expect(cajaB.get('total'), 0);
        final contenidoB = cajaB.values.map((v) => '$v').join(' ');
        expect(contenidoB.contains('Gasto de A'), isFalse);
        expect(contenidoB.contains('token-sintetico'), isFalse);

        // Sin red, B recibe SU copia (vacía), nunca la de A.
        final antes = servidor.peticiones.length;
        servidor.sinRedAlListar = true;
        await g.cargarGastos();
        expect(g.estado.value, EstadoCarga.exito);
        expect(g.desdeCache.value, isTrue);
        expect(g.gastos, isEmpty);
        expect(g.totalEnServidor.value, 0);
        // Y las peticiones de B llevan su propio token, no el de A.
        final tokenB = 'Bearer ${servidor.usuarios['b@ejemplo.com']!.token}';
        expect(servidor.peticiones.skip(antes).every((p) => p.autorizacion == tokenB), isTrue);
      });

      test('si B entra sin red, ve el error: la copia de A ya no existe', () async {
        final g = await aYLuegoB(bSinRed: true);
        expect(auth.estaAutenticado, isTrue);
        expect(g.estado.value, EstadoCarga.error);
        expect(g.desdeCache.value, isFalse);
        expect(g.gastos, isEmpty);
        expect(g.totalEnServidor.value, 0);
        expect(g.mensajeError.value, startsWith('No hay conexión con el servidor'));
      });

      test('una respuesta tardía de A no llega a la lista ni a la caja de B', () async {
        final g = await entrar(dosUsuarios(), correo: 'a@ejemplo.com');
        // A pide recargar y la respuesta (con los gastos de A) se retiene.
        final retenida = Completer<void>();
        servidor
          ..retenerListado = retenida
          ..listadoRecibido = Completer<void>();
        final cargaDeA = g.cargarGastos();
        await servidor.listadoRecibido.future;

        await auth.cerrarSesion();
        servidor.retenerListado = null; // B no se retiene
        await auth.iniciarSesion('b@ejemplo.com', _clave);
        await g.cargaInicial;
        expect(g.gastos, isEmpty);

        // Llega la respuesta tardía de A.
        retenida.complete();
        await cargaDeA;
        expect(g.gastos, isEmpty, reason: 'La lista de B no recibe los gastos de A');
        expect(g.totalEnServidor.value, 0);
        expect(g.estado.value, EstadoCarga.exito);
        expect(g.desdeCache.value, isFalse);
        final contenidoB = Hive.box('gastos_8').values.map((v) => '$v').join(' ');
        expect(contenidoB.contains('Gasto de A'), isFalse, reason: 'Ni la caja de B');
        expect(await Hive.boxExists('gastos_7'), isFalse, reason: 'Ni se recrea la caja de A');
      });
    });
  });

  group('Respuestas tardías tras cerrar sesión (Sesión 8)', () {
    /// Deja una recarga (o «Cargar más») esperando al servidor, cierra sesión
    /// y devuelve la carga pendiente y el `Completer` que la libera.
    Future<(GastosController, Future<void>, Completer<void>)> retenerYSalir(
        {bool paginaSiguiente = false}) async {
      final g = await entrar(_servidor(gastos: _cuarentaYCinco)..paginar = true);
      final retenida = Completer<void>();
      servidor
        ..retenerListado = retenida
        ..listadoRecibido = Completer<void>();
      final carga = paginaSiguiente ? g.cargarMas() : g.cargarGastos();
      await servidor.listadoRecibido.future;
      expect(await auth.cerrarSesion(), isTrue);
      return (g, carga, retenida);
    }

    test('una lista que llega tarde no repone gastos, estado ni caché', () async {
      final (g, carga, retenida) = await retenerYSalir();
      retenida.complete();
      await carga;
      expect(g.gastos, isEmpty);
      expect(g.totalEnServidor.value, 0);
      expect(g.estado.value, EstadoCarga.exito, reason: 'Ni «cargando» ni error');
      expect(g.mensajeError.value, isEmpty);
      expect(Hive.isBoxOpen('gastos_1'), isFalse);
      expect(await Hive.boxExists('gastos_1'), isFalse, reason: 'La caja no se recrea');
    });

    test('un error que llega tarde (sin red) no muestra error ni lee la caja cerrada', () async {
      final (g, carga, retenida) = await retenerYSalir();
      servidor.sinRedAlListar = true;
      retenida.complete();
      await carga;
      expect(g.estado.value, EstadoCarga.exito);
      expect(g.mensajeError.value, isEmpty);
      expect(g.desdeCache.value, isFalse);
    });

    test('una página siguiente que llega tarde no se suma ni deja «cargando más»', () async {
      final (g, carga, retenida) = await retenerYSalir(paginaSiguiente: true);
      retenida.complete();
      await carga;
      expect(g.gastos, isEmpty);
      expect(g.cargandoMas.value, isFalse);
      expect(g.mensajeCargarMas.value, isEmpty);
      expect(await Hive.boxExists('gastos_1'), isFalse);
    });
  });

  group('GastosRepository: vigencia de cada operación', () {
    late GastosRepository repo;
    late ServidorGastosFalso s;

    setUp(() {
      s = _servidor(gastos: _dosGastos);
      final api = ApiClient(dio: s.crearDio())..token = s.usuarios[_correo]!.token;
      repo = GastosRepository(GastosApiService(api));
    });

    test('si se vacía mientras la caja se abre, la apertura no queda en uso y se borra', () async {
      final apertura = repo.abrirParaUsuario(1);
      await repo.vaciar();
      expect(await apertura, isFalse);
      expect(Hive.isBoxOpen('gastos_1'), isFalse);
      expect(await Hive.boxExists('gastos_1'), isFalse);
    });

    test('A sale y entra B mientras se abría la caja de A: solo queda la de B', () async {
      final aperturaA = repo.abrirParaUsuario(7);
      await repo.vaciar();
      final aperturaB = repo.abrirParaUsuario(8);
      expect(await aperturaA, isFalse);
      expect(await aperturaB, isTrue);
      expect(await Hive.boxExists('gastos_7'), isFalse);
      expect(Hive.isBoxOpen('gastos_8'), isTrue);
    });

    test('la misma persona sale y vuelve a entrar mientras se abría: su caja queda en uso', () async {
      final primera = repo.abrirParaUsuario(1);
      await repo.vaciar();
      final segunda = repo.abrirParaUsuario(1);
      expect(await primera, isFalse);
      expect(await segunda, isTrue);
      expect(Hive.isBoxOpen('gastos_1'), isTrue);
      final r = await repo.obtenerGastos();
      expect(r.gastos, hasLength(2));
      expect((Hive.box('gastos_1').get('gastos') as List), hasLength(2));
    });

    test('un 5xx tardío tras cerrar la caja no lee la caja cerrada: el error sube', () async {
      expect(await repo.abrirParaUsuario(1), isTrue);
      await repo.obtenerGastos(); // deja una copia
      final retenida = Completer<void>();
      s
        ..retenerListado = retenida
        ..listadoRecibido = Completer<void>()
        ..falloListar = 503;
      final pendiente = repo.obtenerGastos();
      await s.listadoRecibido.future;
      await repo.vaciar();
      retenida.complete();
      await expectLater(pendiente, throwsA(isA<ApiException>()));
    });
  });

  group('ApiException.desde (dio)', () {
    DioException respuesta(int codigo, Object? cuerpo, {String ruta = '/gastos/'}) {
      final o = RequestOptions(path: ruta);
      return DioException(
        requestOptions: o,
        type: DioExceptionType.badResponse,
        response: Response(requestOptions: o, statusCode: codigo, data: cuerpo),
      );
    }

    test('422 con lista de errores: mensaje legible con el campo', () {
      final e = ApiException.desde(respuesta(422, {
        'detail': [
          {'loc': ['body', 'password'], 'msg': 'String should have at least 8 characters'}
        ]
      }));
      expect(e.statusCode, 422);
      expect(e.mensaje, 'Datos inválidos — password: String should have at least 8 characters');
    });

    test('401 en el login trae el detail; en otra ruta es sesión caducada', () {
      expect(
          ApiException.desde(respuesta(401, {'detail': 'Email o contraseña incorrectos'}, ruta: '/usuarios/token'))
              .mensaje,
          'Email o contraseña incorrectos');
      expect(ApiException.desde(respuesta(401, {'detail': 'x'})).mensaje,
          'Tu sesión caducó, inicia sesión de nuevo.');
    });

    test('5xx, sin conexión y tiempo agotado', () {
      expect(ApiException.desde(respuesta(503, null)).mensaje,
          'El servidor tuvo un problema. Inténtalo más tarde.');
      final o = RequestOptions(path: '/gastos/');
      final sinRed = ApiException.desde(DioException(requestOptions: o, type: DioExceptionType.connectionError));
      expect(sinRed.statusCode, isNull);
      expect(sinRed.mensaje, startsWith('No hay conexión con el servidor'));
      final lento = ApiException.desde(DioException(requestOptions: o, type: DioExceptionType.receiveTimeout));
      expect(lento.statusCode, isNull);
      expect(lento.mensaje, startsWith('El servidor tardó demasiado'));
    });
  });
  group('Restaurar sesión (Paso 4)', () {
    const tokenA = 'token-sintetico-1'; // el del usuario id 1 del servidor falso
    late Box ajustes;

    setUp(() async {
      ajustes = await Hive.openBox('ajustes');
      await ajustes.put('idioma', 'en');
    });

    /// Arranca como la app con [token] en el almacenamiento seguro.
    Future<void> arrancarCon(String token, ServidorGastosFalso s) async {
      FlutterSecureStorage.setMockInitialValues({'access_token': token});
      montar(s);
    }

    test('token válido: recupera el usuario, carga sus gastos y recuerda su id', () async {
      await arrancarCon(tokenA, _servidor(gastos: _dosGastos));
      await auth.restauracion;
      expect(auth.estaAutenticado, isTrue);
      expect(auth.usuario.value!.id, 1);
      expect(auth.restaurando.value, isFalse);
      final g = Get.find<GastosController>();
      await g.cargaInicial;
      expect(g.gastos, hasLength(2));
      expect(SettingsService.ultimoUsuarioId, 1);
      expect(servidor.rutas.first, 'GET /usuarios/me');
    });

    test('401: borra el token y la caja del último usuario; conserva favoritos e idioma', () async {
      // Copia de una sesión anterior (id 1) que nadie abrió en este arranque.
      await (await Hive.openBox('gastos_1')).put('gastos', [_dosGastos.first]);
      await Hive.box('gastos_1').close();
      final favoritos = await Hive.openBox<Map>('favoritos');
      await favoritos.put('lugar-1', {'id': 'lugar-1'});
      await SettingsService.recordarUltimoUsuario(1);

      await arrancarCon('token-caducado', _servidor(gastos: _dosGastos));
      await auth.restauracion;
      await auth.cierrePorCaducidad; // desde el Paso 7 el interceptor también cierra
      expect(auth.estaAutenticado, isFalse);
      expect(auth.avisoSesion.value, 'Tu sesión caducó, inicia sesión de nuevo.');
      expect(await SecureTokenStorage().leer(), isNull);
      expect(Get.find<ApiClient>().token, isNull);
      expect(await Hive.boxExists('gastos_1'), isFalse);
      expect(SettingsService.ultimoUsuarioId, isNull, reason: 'Ya no hace falta');
      expect(favoritos.get('lugar-1'), isNotNull);
      expect(ajustes.get('idioma'), 'en');
      expect(Get.isPrepared<GastosController>(), isTrue, reason: 'No se creó el controller');
    });

    test('si falla el borrado de la caja, se conserva el último id y el reintento la limpia', () async {
      await SettingsService.recordarUltimoUsuario(5);
      // Doble ya usado en las pruebas de widgets: una caja en memoria no admite
      // `deleteFromDisk()`, así que el borrado de `gastos_5` falla.
      await Hive.openBox('gastos_5', bytes: Uint8List(0));
      await arrancarCon('token-caducado', _servidor());
      await auth.restauracion;
      await auth.cierrePorCaducidad;
      expect(auth.estaAutenticado, isFalse);
      expect(await SecureTokenStorage().leer(), isNull, reason: 'El token se borró igual');
      expect(auth.avisoSesion.value, contains('tus gastos guardados'));
      expect(SettingsService.ultimoUsuarioId, 5, reason: 'Se conserva para reintentar');

      // Reintento (el siguiente cierre): ahora sí se borra y el id se olvida.
      expect(await auth.cerrarSesion(), isTrue);
      expect(SettingsService.ultimoUsuarioId, isNull);
    });

    test('sin conexión: conserva el token guardado, avisa y no da la sesión por abierta', () async {
      await SettingsService.recordarUltimoUsuario(1);
      await (await Hive.openBox('gastos_1')).close();
      await arrancarCon(tokenA, _servidor()..sinRed = true);
      await auth.restauracion;
      expect(auth.estaAutenticado, isFalse);
      expect(auth.avisoSesion.value, startsWith('No hay conexión con el servidor'));
      expect(await SecureTokenStorage().leer() == tokenA, isTrue);
      expect(Get.find<ApiClient>().token, isNull);
      expect(await Hive.boxExists('gastos_1'), isTrue, reason: 'Sin 401 no se borra nada');
      expect(SettingsService.ultimoUsuarioId, 1);
    });

    test('una restauración que vuelve tarde, tras cerrar sesión, no la reabre', () async {
      final s = _servidor(gastos: _dosGastos)..retenerPerfil = Completer<void>();
      await arrancarCon(tokenA, s);
      await s.perfilRecibido.future;

      expect(await auth.cerrarSesion(), isTrue);
      s.retenerPerfil!.complete();
      await auth.restauracion;
      expect(auth.estaAutenticado, isFalse);
      expect(auth.restaurando.value, isFalse);
      expect(Get.find<ApiClient>().token, isNull);
      expect(await SecureTokenStorage().leer(), isNull);
    });

    test('iniciar sesión mientras se restaura: la restauración tardía no la pisa', () async {
      final retenida = Completer<void>();
      final s = _servidor(gastos: _dosGastos)..retenerPerfil = retenida;
      await arrancarCon(tokenA, s);
      await s.perfilRecibido.future;
      s.retenerPerfil = null; // el /usuarios/me del login no se retiene
      await auth.iniciarSesion(_correo, _clave);
      expect(auth.estaAutenticado, isTrue);
      final usuarioDelLogin = auth.usuario.value;

      // La respuesta retenida de la restauración llega después.
      retenida.complete();
      await auth.restauracion;
      expect(identical(auth.usuario.value, usuarioDelLogin), isTrue);
      expect(auth.restaurando.value, isFalse);
    });
  });
  group('Categorías y crear (Paso 5)', () {
    test('las categorías vienen del servidor', () async {
      final g = await entrar(_servidor(gastos: _dosGastos));
      expect(g.categorias, ['comida', 'transporte', 'entretenimiento', 'otros']);
    });

    test('un fallo de categorías no impide la lista ni la copia, y se reintenta', () async {
      final g = await entrar(_servidor(gastos: _dosGastos)..falloCategorias = 503);
      expect(g.estado.value, EstadoCarga.exito);
      expect(g.gastos, hasLength(2));
      expect(g.categorias, isEmpty);

      servidor.sinRed = true;
      await g.cargarGastos();
      expect(g.estado.value, EstadoCarga.exito);
      expect(g.desdeCache.value, isTrue);
      expect(g.gastos, hasLength(2));

      servidor
        ..sinRed = false
        ..falloCategorias = null;
      await g.cargarGastos();
      expect(g.categorias, isNotEmpty);
      expect(g.desdeCache.value, isFalse);
    });

    test('crear envía el gasto, recarga la primera página y actualiza la copia', () async {
      final g = await entrar(_servidor(gastos: _dosGastos));
      final antes = servidor.peticiones.length;
      await g.crear('Almuerzo en el Mercado Central', 6.5, 'comida');

      final post = servidor.peticiones.singleWhere((p) => p.metodo == 'POST' && p.ruta == '/gastos/');
      expect(post.cuerpo, '{"descripcion":"Almuerzo en el Mercado Central","monto":6.5,"categoria":"comida"}');
      expect(servidor.rutas.sublist(antes), ['POST /gastos/', 'GET /gastos/']);
      expect(servidor.consultasDeListado.last, {'skip': '0', 'limit': '20'});
      expect(g.gastos.map((x) => x.descripcion), contains('Almuerzo en el Mercado Central'));
      expect(g.totalEnServidor.value, 3);
      final copia = Hive.box('gastos_1').get('gastos') as List;
      expect(copia, hasLength(3));
      expect(Hive.box('gastos_1').get('total'), 3);
    });

    test('rechazo del servidor (límite de 500): el mensaje sube y no se recarga nada', () async {
      final g = await entrar(_servidor());
      await g.crear('Cena grande', 450, 'comida');
      final antes = servidor.peticiones.length;
      await expectLater(g.crear('Otra cena', 100, 'comida'),
          throwsA(predicate((e) => e is ApiException && e.mensaje.contains('supera el límite de 500.0'))));
      expect(servidor.rutas.sublist(antes), ['POST /gastos/']);
      expect(g.gastos.map((x) => x.descripcion).toList(), ['Cena grande']);
    });

    test('aceptado pero falla la recarga: no se informa como fallo al crear', () async {
      final g = await entrar(_servidor(gastos: _dosGastos));
      servidor.falloListar = 400;
      await g.crear('Taxi al aeropuerto', 12, 'transporte'); // no lanza
      expect(servidor.usuarios[_correo]!.gastos, hasLength(3));
      expect(g.estado.value, EstadoCarga.error);
      expect(g.mensajeError.value, isNotEmpty);
    });

    test('sin conexión no se crea nada: el error sube y la copia no cambia', () async {
      final g = await entrar(_servidor(gastos: _dosGastos));
      servidor.sinRed = true;
      await expectLater(g.crear('Café', 2, 'comida'),
          throwsA(predicate((e) => e is ApiException && e.mensaje.startsWith('No hay conexión'))));
      expect((Hive.box('gastos_1').get('gastos') as List), hasLength(2));
      expect(g.gastos, hasLength(2));
    });
  });
  group('Editar y eliminar (Paso 6)', () {
    List<String> nuevasRutas(int desde) => servidor.rutas.sublist(desde);

    test('editar envía SOLO los campos que cambiaron, recarga y actualiza la copia', () async {
      final g = await entrar(_servidor(gastos: _dosGastos));
      final antes = servidor.peticiones.length;
      await g.actualizar(2, {'monto': 4.0});
      final patch = servidor.peticiones.singleWhere((p) => p.metodo == 'PATCH');
      expect(patch.ruta, '/gastos/2');
      expect(patch.cuerpo, '{"monto":4.0}');
      expect(nuevasRutas(antes), ['PATCH /gastos/2', 'GET /gastos/']);
      expect(servidor.consultasDeListado.last, {'skip': '0', 'limit': '20'});
      expect(g.gastos.singleWhere((x) => x.id == 2).monto, 4.0);
      expect(g.gastos.singleWhere((x) => x.id == 2).descripcion, 'Taxi');
      final copia = (Hive.box('gastos_1').get('gastos') as List).cast<Map>();
      expect(copia.singleWhere((m) => m['id'] == 2)['monto'], 4.0);
    });

    test('eliminar acepta el 204 sin cuerpo, recarga y lo quita de la copia', () async {
      final g = await entrar(_servidor(gastos: _dosGastos));
      final antes = servidor.peticiones.length;
      await g.eliminar(1);
      expect(nuevasRutas(antes), ['DELETE /gastos/1', 'GET /gastos/']);
      expect(g.gastos.map((x) => x.id).toList(), [2]);
      expect(g.totalEnServidor.value, 1);
      expect((Hive.box('gastos_1').get('gastos') as List), hasLength(1));
    });

    test('404 al editar: recarga la lista y el mensaje del servidor sube', () async {
      final g = await entrar(_servidor(gastos: _dosGastos));
      servidor.usuarios[_correo]!.gastos.removeWhere((x) => x['id'] == 2); // borrado en otro lado
      await expectLater(g.actualizar(2, {'monto': 9.0}),
          throwsA(predicate((e) => e is ApiException && e.statusCode == 404 && e.mensaje == 'El gasto 2 no existe')));
      expect(g.gastos.map((x) => x.id).toList(), [1], reason: 'La lista ya no lo muestra');
    });

    test('404 al eliminar: recarga la lista y el mensaje del servidor sube', () async {
      final g = await entrar(_servidor(gastos: _dosGastos));
      servidor.usuarios[_correo]!.gastos.clear();
      await expectLater(g.eliminar(1),
          throwsA(predicate((e) => e is ApiException && e.mensaje == 'El gasto 1 no existe')));
      expect(g.gastos, isEmpty);
    });

    test('aceptado pero falla la recarga: editar y eliminar no se informan como fallidos', () async {
      final g = await entrar(_servidor(gastos: _dosGastos));
      servidor.falloListar = 400;
      await g.actualizar(1, {'descripcion': 'Almuerzo largo'}); // no lanza
      await g.eliminar(2); // no lanza
      expect(servidor.usuarios[_correo]!.gastos.map((x) => x['descripcion']), ['Almuerzo largo']);
      expect(g.estado.value, EstadoCarga.error);
    });
  });
  group('Interceptor del 401 (Paso 7)', () {
    test('un 401 del login solo muestra el error de credenciales', () async {
      await entrar(_servidor(), clave: 'otra-clave-1');
      expect(auth.mensajeError.value, 'Email o contraseña incorrectos');
      expect(auth.avisoSesion.value, isEmpty);
      expect(auth.cierrePorCaducidad, isNull, reason: 'No hubo cierre por caducidad');
    });

    test('un 401 tardío de la sesión anterior no cierra la nueva', () async {
      final s = ServidorGastosFalso({
        'a@ejemplo.com': UsuarioFalso(id: 7, password: _clave, gastos: List.of(_dosGastos)),
        'b@ejemplo.com': UsuarioFalso(id: 8, password: _clave),
      });
      final g = await entrar(s, correo: 'a@ejemplo.com');
      final retenida = Completer<void>();
      s
        ..retenerListado = retenida
        ..listadoRecibido = Completer<void>();
      final cargaDeA = g.cargarGastos();
      await s.listadoRecibido.future;

      await auth.cerrarSesion();
      s.retenerListado = null;
      await auth.iniciarSesion('b@ejemplo.com', _clave);
      await g.cargaInicial;

      s.falloListar = 401; // la respuesta tardía de A es un 401
      retenida.complete();
      await cargaDeA;
      expect(auth.cierrePorCaducidad, isNull);
      expect(auth.estaAutenticado, isTrue);
      expect(auth.usuario.value!.id, 8);
      expect(auth.avisoSesion.value, isEmpty);
    });

    test('varios 401 a la vez hacen un solo cierre y un solo borrado del token', () async {
      final almacen = _AlmacenQueCuentaBorrados();
      montar(_servidor(gastos: _dosGastos), almacen: almacen);
      await auth.iniciarSesion(_correo, _clave);
      final borradosAntes = almacen.borrados;
      servidor.falloListar = 401;
      final api = Get.find<ApiClient>();
      await Future.wait([
        api.get('/gastos/').then((_) {}, onError: (_) {}),
        api.get('/gastos/').then((_) {}, onError: (_) {}),
        api.get('/gastos/').then((_) {}, onError: (_) {}),
      ]);
      await auth.cierrePorCaducidad;
      expect(auth.estaAutenticado, isFalse);
      expect(almacen.borrados - borradosAntes, 1);
      expect(auth.avisoSesion.value, 'Tu sesión caducó, inicia sesión de nuevo.');
    });

    test('sin red y 5xx no cierran la sesión y conservan el respaldo', () async {
      final g = await entrar(_servidor(gastos: _dosGastos));
      for (final provocar in <void Function()>[
        () => servidor.sinRed = true,
        () => servidor.falloListar = 503,
      ]) {
        servidor
          ..sinRed = false
          ..falloListar = null;
        provocar();
        await g.cargarGastos();
        expect(auth.cierrePorCaducidad, isNull);
        expect(auth.estaAutenticado, isTrue);
        expect(g.desdeCache.value, isTrue);
        expect(g.gastos, hasLength(2));
      }
    });

    test('un 401 al crear cierra la sesión (no es un error de negocio)', () async {
      final g = await entrar(_servidor(gastos: _dosGastos));
      Get.find<ApiClient>().token = 'token-invalido'; // «Invalidar token (solo práctica)»
      await expectLater(g.crear('Café', 2, 'comida'), throwsA(isA<ApiException>()));
      await auth.cierrePorCaducidad;
      expect(auth.estaAutenticado, isFalse);
      expect(servidor.usuarios[_correo]!.gastos, hasLength(2));
    });
  });
}
