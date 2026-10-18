import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:exploraec/controllers/gastos_controller.dart';
import 'package:exploraec/controllers/places_controller.dart' show EstadoCarga;
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:hive/hive.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

// Token sintético: las pruebas solo lo comparan, nunca lo imprimen.
const _token = 'token-sintetico-de-prueba';

http.Response _json(Object body, int code, {Map<String, String> h = const {}}) =>
    http.Response(jsonEncode(body), code, headers: {'content-type': 'application/json', ...h});

/// Una petición recibida por el servidor falso, para comprobar orden y formato.
class _Peticion {
  final String metodo;
  final String ruta;
  final Map<String, String> query;
  final Map<String, String> cabeceras;
  final String cuerpo;
  _Peticion(http.Request r)
      : metodo = r.method,
        ruta = r.url.path,
        query = r.url.queryParameters,
        cabeceras = r.headers,
        cuerpo = r.body;

  @override
  String toString() => '$metodo $ruta';
}

/// Servidor falso: usuarios y gastos en memoria según el contrato real.
/// Registra cada petición en [peticiones].
MockClient _servidor({
  List<Map<String, dynamic>> gastos = const [],
  int? total,
  bool registroDuplicado = false,
  int? falloRegistro,
  int? falloLogin,
  bool sinRed = false,
  int? falloListar,
  int? falloPerfil,
  bool sinRedAlListar = false,
  bool timeoutAlListar = false,
  bool paginar = false,
  int solapar = 0,
  List<_Peticion>? peticiones,
  Completer<void>? retenerLogin,
}) {
  return MockClient((req) async {
    peticiones?.add(_Peticion(req));
    if (sinRed) throw const SocketException('sin red');
    final ruta = req.url.path;
    if (ruta == '/usuarios/' && req.method == 'POST') {
      expect(req.headers['content-type'], contains('application/json'));
      final b = jsonDecode(req.body) as Map;
      if ((b['password'] as String).length < 8) {
        return _json({'detail': [{'type': 'string_too_short', 'loc': ['body', 'password'], 'msg': 'String should have at least 8 characters'}]}, 422);
      }
      if (falloRegistro != null) return _json({'detail': 'x'}, falloRegistro);
      if (registroDuplicado) return _json({'detail': 'El email ya está registrado'}, 400);
      return _json({'id': 1, 'email': b['email']}, 201);
    }
    if (ruta == '/usuarios/token') {
      expect(req.headers['content-type'], contains('application/x-www-form-urlencoded'));
      expect(req.bodyFields['username'], isNotEmpty);
      if (retenerLogin != null) await retenerLogin.future;
      if (falloLogin != null) return _json({'detail': 'Credenciales incorrectas'}, falloLogin);
      return _json({'access_token': _token, 'token_type': 'bearer'}, 200);
    }
    if (ruta == '/usuarios/me') {
      // Sesión 7: el id da nombre a la caja `gastos_<id>`; exige el token.
      expect(req.headers['authorization'], 'Bearer $_token');
      if (falloPerfil != null) return _json({'detail': 'x'}, falloPerfil);
      return _json({'id': 1, 'email': 'a@b.com'}, 200);
    }
    if (ruta == '/gastos/') {
      if (sinRedAlListar) throw const SocketException('sin red');
      // El handler lanza lo mismo que `.timeout(...)` al agotarse el plazo.
      if (timeoutAlListar) throw TimeoutException('sin respuesta');
      if (falloListar != null) return _json({'detail': 'x'}, falloListar);
      expect(req.headers['authorization'], 'Bearer $_token');
      var pagina = gastos;
      if (paginar) {
        // Como el backend: `skip`/`limit` recortan la lista. `solapar` imita
        // un gasto nuevo entre dos páginas (el desplazamiento repite uno).
        final skip = int.parse(req.url.queryParameters['skip'] ?? '0');
        final limit = int.parse(req.url.queryParameters['limit'] ?? '20');
        final desde = (skip - solapar).clamp(0, gastos.length);
        pagina = gastos.sublist(desde, (desde + limit).clamp(0, gastos.length));
      }
      return _json(pagina, 200, h: {'x-total-count': '${total ?? gastos.length}'});
    }
    return _json({'detail': 'no existe'}, 404);
  });
}

/// Un usuario sintético del servidor multiusuario.
class _Usuario {
  final int id;
  final String token;
  final List<Map<String, dynamic>> gastos;
  final int total;
  const _Usuario(this.id, this.token, this.gastos, this.total);
}

/// Servidor falso con varios usuarios: el login devuelve el token del
/// correo, `/usuarios/me` y `/gastos/` responden según ese token. Así se
/// comprueba que nada de un usuario se filtra al siguiente.
MockClient _servidorMultiusuario(
  Map<String, _Usuario> usuarios, {
  bool sinRedAlListar = false,
  List<_Peticion>? peticiones,
}) {
  return MockClient((req) async {
    peticiones?.add(_Peticion(req));
    final ruta = req.url.path;
    if (ruta == '/usuarios/' && req.method == 'POST') {
      return _json({'detail': 'El email ya está registrado'}, 400);
    }
    if (ruta == '/usuarios/token') {
      final u = usuarios[req.bodyFields['username']];
      if (u == null) return _json({'detail': 'Credenciales incorrectas'}, 401);
      return _json({'access_token': u.token, 'token_type': 'bearer'}, 200);
    }
    final autorizacion = req.headers['authorization'];
    final usuario = usuarios.values.where((u) => autorizacion == 'Bearer ${u.token}');
    if (usuario.isEmpty) return _json({'detail': 'No autenticado'}, 401);
    final u = usuario.single;
    if (ruta == '/usuarios/me') return _json({'id': u.id, 'email': 'x'}, 200);
    if (ruta == '/gastos/') {
      if (sinRedAlListar) throw const SocketException('sin red');
      return _json(u.gastos, 200, h: {'x-total-count': '${u.total}'});
    }
    return _json({'detail': 'no existe'}, 404);
  });
}

/// 45 gastos sintéticos (ids 1..45): tres páginas de 20, 20 y 5.
final _cuarentaYCinco = List.generate(
  45,
  (i) => {'id': i + 1, 'descripcion': 'Gasto ${i + 1}', 'monto': 1 + i, 'categoria': 'comida', 'fecha': '2026-10-18'},
);

/// Consultas (`skip`/`limit`) de cada `GET /gastos/` recibido.
List<Map<String, String>> _consultasDeListado(List<_Peticion> peticiones) =>
    peticiones.where((p) => p.ruta == '/gastos/').map((p) => p.query).toList();

const _dosGastos = [
  {'id': 1, 'descripcion': 'Almuerzo', 'monto': 6.5, 'categoria': 'comida', 'fecha': '2026-10-05'},
  {'id': 2, 'descripcion': 'Taxi', 'monto': 3, 'categoria': 'transporte', 'fecha': '2026-10-05'},
];

void main() {
  // Carpeta temporal propia de este archivo: Hive nunca escribe fuera de ella.
  late Directory carpetaHive;
  setUpAll(() {
    carpetaHive = Directory.systemTemp.createTempSync('exploraec_hive_gastos_');
    Hive.init(carpetaHive.path);
  });
  setUp(() async {
    Get.testMode = true;
    // Cierra y borra las cajas abiertas (todas viven en `carpetaHive`):
    // cada prueba parte sin ninguna caja.
    await Hive.deleteFromDisk();
  });
  tearDownAll(() async {
    await Hive.close();
    if (carpetaHive.existsSync()) carpetaHive.deleteSync(recursive: true);
  });

  Future<GastosController> entrar(MockClient c, {String pass = 'clave-1234'}) async {
    final g = GastosController();
    await http.runWithClient(() => g.entrar('a@b.com', pass), () => c);
    return g;
  }

  // ---- Pruebas del starter (Sesión 6) ----

  test('usuario nuevo: registro -> login -> lista vacía', () async {
    final g = await entrar(_servidor());
    expect(g.sesionActiva.value, isTrue);
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

  test('400 al registrar (correo existente) se ignora y sigue al login', () async {
    final g = await entrar(_servidor(registroDuplicado: true));
    expect(g.sesionActiva.value, isTrue);
  });

  test('422 al registrar: mensaje legible con el campo, sin sesión', () async {
    final g = await entrar(_servidor(), pass: 'abc');
    expect(g.sesionActiva.value, isFalse);
    expect(g.mensajeAuth.value, startsWith('Datos inválidos — password:'));
  });

  // Sesión 7 (Paso 2): sin copia guardada sigue siendo error; con copia,
  // ver «Paginación y copia local».
  test('sin conexión y sin copia: error legible y la sesión no se pierde', () async {
    final g = await entrar(_servidor(sinRedAlListar: true));
    expect(g.estado.value, EstadoCarga.error);
    expect(g.mensajeError.value, startsWith('No hay conexión con el servidor'));
    expect(g.sesionActiva.value, isTrue);
    expect(g.desdeCache.value, isFalse);
  });

  test('401 al listar: vuelve al formulario y explica por qué', () async {
    final g = await entrar(_servidor());
    await http.runWithClient(() => g.cargarGastos(), () => _servidor(falloListar: 401));
    expect(g.sesionActiva.value, isFalse);
    expect(g.mensajeAuth.value, startsWith('Tu sesión caducó'));
  });

  test('5xx sin copia: mensaje genérico', () async {
    final g = await entrar(_servidor(falloListar: 503));
    expect(g.estado.value, EstadoCarga.error);
    expect(g.desdeCache.value, isFalse);
    expect(g.mensajeError.value, 'El servidor tuvo un problema. Inténtalo más tarde.');
  });

  // ---- Comprobaciones adicionales (Paso 7) ----

  group('Orden y formato de las peticiones', () {
    test('registro -> login -> perfil -> listado, en ese orden y desde skip 0', () async {
      final peticiones = <_Peticion>[];
      await entrar(_servidor(gastos: _dosGastos, peticiones: peticiones));

      expect(peticiones.map((p) => '$p').toList(),
          ['POST /usuarios/', 'POST /usuarios/token', 'GET /usuarios/me', 'GET /gastos/']);
      expect(peticiones.last.query, {'skip': '0', 'limit': '20'});
    });

    test('registro en JSON, login en formulario y listado con Bearer', () async {
      final peticiones = <_Peticion>[];
      await entrar(_servidor(peticiones: peticiones));
      final registro = peticiones[0];
      final login = peticiones[1];
      final perfil = peticiones.singleWhere((p) => p.ruta == '/usuarios/me');
      final listado = peticiones.singleWhere((p) => p.ruta == '/gastos/');

      expect(registro.cabeceras['content-type'], contains('application/json'));
      expect(jsonDecode(registro.cuerpo), {'email': 'a@b.com', 'password': 'clave-1234'});

      expect(login.cabeceras['content-type'], contains('application/x-www-form-urlencoded'));
      expect(Uri.splitQueryString(login.cuerpo),
          {'username': 'a@b.com', 'password': 'clave-1234'});
      expect(login.cuerpo.trimLeft().startsWith('{'), isFalse, reason: 'No debe ir en JSON');

      // Se compara sin imprimir el token: solo un booleano en el mensaje.
      final autorizacion = listado.cabeceras['authorization'] ?? '';
      expect(autorizacion.startsWith('Bearer '), isTrue);
      expect(autorizacion == 'Bearer $_token', isTrue);
      expect(perfil.metodo, 'GET');
      expect(perfil.cabeceras['authorization'] == 'Bearer $_token', isTrue);
      expect(registro.cabeceras.containsKey('authorization'), isFalse);
      expect(login.cabeceras.containsKey('authorization'), isFalse);
    });

    test('correo existente (400): no repite el registro y continúa al login', () async {
      final peticiones = <_Peticion>[];
      final g = await entrar(_servidor(registroDuplicado: true, peticiones: peticiones));
      expect(peticiones.map((p) => '$p').toList(),
          ['POST /usuarios/', 'POST /usuarios/token', 'GET /usuarios/me', 'GET /gastos/']);
      expect(g.sesionActiva.value, isTrue);
      expect(g.mensajeAuth.value, isEmpty);
    });
  });

  group('Errores que impiden continuar', () {
    test('5xx al registrar: no intenta el login ni el listado', () async {
      final peticiones = <_Peticion>[];
      final g = await entrar(_servidor(falloRegistro: 500, peticiones: peticiones));
      expect(peticiones.map((p) => '$p').toList(), ['POST /usuarios/']);
      expect(g.sesionActiva.value, isFalse);
      expect(g.mensajeAuth.value, 'El servidor tuvo un problema. Inténtalo más tarde.');
      expect(g.autenticando.value, isFalse);
    });

    test('credenciales incorrectas (401 en login): no lista y sigue sin sesión', () async {
      final peticiones = <_Peticion>[];
      final g = await entrar(
          _servidor(registroDuplicado: true, falloLogin: 401, peticiones: peticiones));
      expect(peticiones.map((p) => '$p').toList(),
          ['POST /usuarios/', 'POST /usuarios/token']);
      expect(g.sesionActiva.value, isFalse);
      expect(g.mensajeAuth.value, startsWith('Tu sesión caducó o las credenciales no son válidas'));
      expect(g.autenticando.value, isFalse);
    });

    test('sin conexión al entrar: mensaje legible y autenticando vuelve a false', () async {
      final peticiones = <_Peticion>[];
      final g = await entrar(_servidor(sinRed: true, peticiones: peticiones));
      expect(peticiones, hasLength(1));
      expect(g.sesionActiva.value, isFalse);
      expect(g.mensajeAuth.value, startsWith('No hay conexión con el servidor'));
      expect(g.autenticando.value, isFalse);
    });
  });

  group('autenticando', () {
    test('es true mientras el flujo espera y false al terminar', () async {
      final retener = Completer<void>();
      final g = GastosController();
      final flujo = http.runWithClient(
        () => g.entrar('a@b.com', 'clave-1234'),
        () => _servidor(retenerLogin: retener),
      );
      // El login queda en espera: el flujo sigue en marcha.
      await Future<void>.delayed(Duration.zero);
      expect(g.autenticando.value, isTrue);
      expect(g.sesionActiva.value, isFalse);

      retener.complete();
      await flujo;
      expect(g.autenticando.value, isFalse);
      expect(g.sesionActiva.value, isTrue);
    });

    test('vuelve a false tras cada tipo de error y permite reintentar', () async {
      final g = GastosController();
      for (final servidor in [
        _servidor(sinRed: true),
        _servidor(falloRegistro: 503),
        _servidor(registroDuplicado: true, falloLogin: 401),
      ]) {
        await http.runWithClient(() => g.entrar('a@b.com', 'clave-1234'), () => servidor);
        expect(g.autenticando.value, isFalse);
        expect(g.sesionActiva.value, isFalse);
        expect(g.mensajeAuth.value, isNotEmpty);
      }
      // Un reintento correcto limpia el mensaje y entra.
      await http.runWithClient(() => g.entrar('a@b.com', 'clave-1234'), () => _servidor());
      expect(g.sesionActiva.value, isTrue);
      expect(g.mensajeAuth.value, isEmpty);
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

      // Sesión 7: sin red, tiempo agotado o 5xx caen a la copia (éxito con
      // `desdeCache`), ya no a la pantalla de error.
      for (final fallo in [
        _servidor(sinRed: true),
        _servidor(timeoutAlListar: true),
        _servidor(falloListar: 503),
      ]) {
        await http.runWithClient(() => g.cargarGastos(), () => fallo);
        expect(g.estado.value, EstadoCarga.exito);
        expect(g.desdeCache.value, isTrue);
        expect(g.gastos.map((x) => x.descripcion).toList(), ['Almuerzo', 'Taxi']);
        expect(g.totalEnServidor.value, 2);
        expect(g.sesionActiva.value, isTrue);
      }

      // Al recuperarse, vuelve a los datos del servidor y el aviso se apaga.
      await http.runWithClient(() => g.cargarGastos(), () => _servidor(gastos: _dosGastos));
      expect(g.estado.value, EstadoCarga.exito);
      expect(g.desdeCache.value, isFalse);
    });

    test('401 al recargar: vuelve al formulario con el mensaje, sin borrar la lista', () async {
      final g = await entrar(_servidor(gastos: _dosGastos));
      await http.runWithClient(() => g.cargarGastos(), () => _servidor(falloListar: 401));
      expect(g.sesionActiva.value, isFalse);
      expect(g.estado.value, EstadoCarga.error);
      expect(g.mensajeAuth.value, startsWith('Tu sesión caducó'));
      expect(g.mensajeError.value, g.mensajeAuth.value);
      expect(g.gastos, hasLength(2));
    });
  });
  // ---- Sesión 7: caja de Hive por usuario (Punto de partida / Paso 1) ----

  group('Caja de Hive por usuario', () {
    test('al entrar se abre la caja gastos_<id> con el id de /usuarios/me', () async {
      final g = await entrar(_servidor(gastos: _dosGastos));
      expect(g.sesionActiva.value, isTrue);
      expect(Hive.isBoxOpen('gastos_1'), isTrue);
      expect(await Hive.boxExists('gastos_1'), isTrue);
    });

    test('el token no se guarda en Hive', () async {
      await entrar(_servidor(gastos: _dosGastos));
      final caja = Hive.box('gastos_1');
      final contenido = [...caja.keys, ...caja.values].map((x) => '$x').join(' ');
      // Solo booleanos en el mensaje: el token nunca se imprime.
      expect(contenido.contains(_token), isFalse);
      expect(caja.keys.any((k) => '$k'.toLowerCase().contains('token')), isFalse);
    });

    test('perfil inaccesible (5xx en /usuarios/me): no entra ni pide el listado', () async {
      final peticiones = <_Peticion>[];
      final g = await entrar(_servidor(falloPerfil: 503, peticiones: peticiones));
      expect(peticiones.map((p) => '$p').toList(),
          ['POST /usuarios/', 'POST /usuarios/token', 'GET /usuarios/me']);
      expect(g.sesionActiva.value, isFalse);
      expect(g.mensajeAuth.value, 'El servidor tuvo un problema. Inténtalo más tarde.');
      expect(g.autenticando.value, isFalse);
    });
  });

  group('Paginación y copia local (Paso 2)', () {
    test('respaldo tras cargar varias páginas: copia de 40 de 45, sin «Cargar más»', () async {
      final peticiones = <_Peticion>[];
      final g = await entrar(_servidor(gastos: _cuarentaYCinco, paginar: true, peticiones: peticiones));
      expect(g.gastos, hasLength(20));
      expect(g.totalEnServidor.value, 45);
      expect(g.hayMas, isTrue);

      await http.runWithClient(() => g.cargarMas(),
          () => _servidor(gastos: _cuarentaYCinco, paginar: true, peticiones: peticiones));
      expect(g.gastos.map((x) => x.id).toList(), List.generate(40, (i) => i + 1));
      expect(_consultasDeListado(peticiones), [
        {'skip': '0', 'limit': '20'},
        {'skip': '20', 'limit': '20'},
      ]);

      // La copia en Hive es exactamente lo que está a la vista, con el total.
      final caja = Hive.box('gastos_1');
      expect((caja.get('gastos') as List), hasLength(40));
      expect(caja.get('total'), 45);
      expect(caja.get('sincronizado'), isA<String>());

      final sinRed = <_Peticion>[];
      await http.runWithClient(() => g.cargarGastos(), () => _servidor(sinRed: true, peticiones: sinRed));
      expect(g.estado.value, EstadoCarga.exito);
      expect(g.desdeCache.value, isTrue);
      expect(g.gastos.map((x) => x.id).toList(), List.generate(40, (i) => i + 1));
      expect(g.totalEnServidor.value, 45, reason: 'El total conocido se conserva como metadato');
      expect(g.hayMas, isFalse, reason: 'Con la copia a la vista no se ofrece «Cargar más»');

      // Y aunque se llame, no pide nada ni cambia la lista.
      sinRed.clear();
      await http.runWithClient(() => g.cargarMas(), () => _servidor(sinRed: true, peticiones: sinRed));
      expect(sinRed, isEmpty);
      expect(g.gastos, hasLength(40));
    });

    test('una recarga exitosa reemplaza la copia anterior', () async {
      final g = await entrar(_servidor(gastos: _cuarentaYCinco, paginar: true));
      await http.runWithClient(() => g.cargarMas(), () => _servidor(gastos: _cuarentaYCinco, paginar: true));
      expect(g.gastos, hasLength(40));

      // El servidor ahora tiene solo 2 gastos: la copia de 40 desaparece.
      await http.runWithClient(() => g.cargarGastos(), () => _servidor(gastos: _dosGastos));
      expect(g.gastos.map((x) => x.descripcion).toList(), ['Almuerzo', 'Taxi']);
      expect(g.totalEnServidor.value, 2);
      expect(g.desdeCache.value, isFalse);

      await http.runWithClient(() => g.cargarGastos(), () => _servidor(sinRed: true));
      expect(g.desdeCache.value, isTrue);
      expect(g.gastos.map((x) => x.descripcion).toList(), ['Almuerzo', 'Taxi']);
      expect(g.totalEnServidor.value, 2);
    });

    test('un fallo de página adicional conserva lo mostrado, avisa y no duplica', () async {
      final peticiones = <_Peticion>[];
      final g = await entrar(_servidor(gastos: _cuarentaYCinco, paginar: true));
      final primeraPagina = List.generate(20, (i) => i + 1);

      for (final fallo in [
        _servidor(sinRed: true, peticiones: peticiones),
        _servidor(timeoutAlListar: true, peticiones: peticiones),
        _servidor(falloListar: 503, peticiones: peticiones),
      ]) {
        await http.runWithClient(() => g.cargarMas(), () => fallo);
        expect(g.gastos.map((x) => x.id).toList(), primeraPagina);
        expect(g.estado.value, EstadoCarga.exito);
        expect(g.desdeCache.value, isFalse, reason: 'No se presenta la copia como página siguiente');
        expect(g.totalEnServidor.value, 45);
        expect(g.hayMas, isTrue);
        expect(g.mensajeCargarMas.value, isNotEmpty);
        expect(g.cargandoMas.value, isFalse);
      }
      // Cada intento pidió la página siguiente (skip 20), nunca la primera.
      expect(_consultasDeListado(peticiones).map((q) => q['skip']).toSet(), {'20'});

      // El reintento correcto suma la página sin repetir y limpia el aviso.
      await http.runWithClient(() => g.cargarMas(), () => _servidor(gastos: _cuarentaYCinco, paginar: true));
      expect(g.gastos.map((x) => x.id).toList(), List.generate(40, (i) => i + 1));
      expect(g.mensajeCargarMas.value, isEmpty);

      // La copia guardada también quedó con 40, sin duplicados.
      await http.runWithClient(() => g.cargarGastos(), () => _servidor(sinRed: true));
      final ids = g.gastos.map((x) => x.id).toList();
      expect(ids, hasLength(40));
      expect(ids.toSet(), hasLength(40));
    });

    test('una página que repite un gasto ya mostrado no lo duplica', () async {
      final g = await entrar(_servidor(gastos: _cuarentaYCinco, paginar: true));
      // Llega 20..39: el 20 ya estaba a la vista.
      await http.runWithClient(
          () => g.cargarMas(), () => _servidor(gastos: _cuarentaYCinco, paginar: true, solapar: 1));
      final ids = g.gastos.map((x) => x.id).toList();
      expect(ids, List.generate(39, (i) => i + 1));
      expect(ids.toSet(), hasLength(ids.length));
      expect(g.hayMas, isTrue);
    });

    test('una copia de lista vacía también es una copia válida', () async {
      final g = await entrar(_servidor());
      expect(await Hive.boxExists('gastos_1'), isTrue);
      for (final fallo in [_servidor(sinRed: true), _servidor(falloListar: 503)]) {
        await http.runWithClient(() => g.cargarGastos(), () => fallo);
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
        await http.runWithClient(() => g.cargarGastos(), () => _servidor(falloListar: codigo));
        expect(g.estado.value, EstadoCarga.error, reason: 'HTTP $codigo');
        expect(g.desdeCache.value, isFalse, reason: 'HTTP $codigo');
        expect(g.mensajeError.value, isNotEmpty);
        expect(g.sesionActiva.value, isTrue);
      }
    });

    test('tras mostrar la copia, un 401 vuelve al formulario sin usarla', () async {
      final g = await entrar(_servidor(gastos: _dosGastos));
      await http.runWithClient(() => g.cargarGastos(), () => _servidor(sinRed: true));
      expect(g.desdeCache.value, isTrue);
      await http.runWithClient(() => g.cargarGastos(), () => _servidor(falloListar: 401));
      expect(g.sesionActiva.value, isFalse);
      expect(g.desdeCache.value, isFalse);
      expect(g.estado.value, EstadoCarga.error);
      expect(g.mensajeAuth.value, startsWith('Tu sesión caducó'));
    });
  });

  // ---- Pruebas del starter (Sesión 7) ----
  // «Paso 5 — cerrar sesión borra la caja del usuario» falla A PROPÓSITO
  // hasta conectar `salir()` a `vaciar()` (Paso 5). No se omite ni se relaja.

  test('5xx sin nada en caché: error legible', () async {
    final g = await entrar(_servidor(falloListar: 503));
    expect(g.estado.value, EstadoCarga.error);
    expect(g.mensajeError.value, 'El servidor tuvo un problema. Inténtalo más tarde.');
  });

  test('Paso 2 — sin conexión con caché: muestra lo guardado y marca desdeCache', () async {
    final g = await entrar(_servidor(gastos: _dosGastos));
    await http.runWithClient(() => g.cargarGastos(), () => _servidor(sinRed: true));
    expect(g.estado.value, EstadoCarga.exito);
    expect(g.desdeCache.value, isTrue);
    expect(g.gastos.length, 2);
    expect(g.ultimaSincronizacion, isNot('desconocida'));
  });

  test('Paso 2 — 5xx con caché: también cae a la caché', () async {
    final g = await entrar(_servidor(gastos: _dosGastos));
    await http.runWithClient(() => g.cargarGastos(), () => _servidor(falloListar: 503));
    expect(g.desdeCache.value, isTrue);
    expect(g.gastos.length, 2);
  });

  test('Paso 2 — al volver el servidor, el banner desaparece', () async {
    final g = await entrar(_servidor(gastos: _dosGastos));
    await http.runWithClient(() => g.cargarGastos(), () => _servidor(sinRed: true));
    await http.runWithClient(() => g.cargarGastos(), () => _servidor(gastos: _dosGastos));
    expect(g.desdeCache.value, isFalse);
  });

  test('Paso 2 — un 401 NO usa la caché: vuelve al formulario', () async {
    final g = await entrar(_servidor(gastos: _dosGastos));
    await http.runWithClient(() => g.cargarGastos(), () => _servidor(falloListar: 401));
    expect(g.sesionActiva.value, isFalse);
    expect(g.desdeCache.value, isFalse);
    expect(g.mensajeAuth.value, startsWith('Tu sesión caducó'));
  });

  test('Paso 5 — cerrar sesión borra la caja del usuario', () async {
    final g = await entrar(_servidor(gastos: _dosGastos));
    expect(await Hive.boxExists('gastos_1'), isTrue);
    await g.salir();
    expect(await Hive.boxExists('gastos_1'), isFalse);
    expect(g.sesionActiva.value, isFalse);
  });
  // ---- Sesión 7, Paso 5: cerrar sesión borra la caja del usuario ----

  group('Cerrar sesión (Paso 5)', () {
    File archivoCaja(String nombre) => File('${carpetaHive.path}${Platform.pathSeparator}$nombre.hive');

    test('borra gastos_<id> del disco, conserva favoritos y limpia el estado', () async {
      // La caja de favoritos de la app, con un lugar marcado (en la misma
      // carpeta temporal).
      final favoritos = await Hive.openBox<Map>('favoritos');
      await favoritos.put('lugar-1', {'id': 'lugar-1', 'nombre': 'Mitad del Mundo'});

      final g = await entrar(_servidor(gastos: _cuarentaYCinco, paginar: true));
      await http.runWithClient(() => g.cargarMas(), () => _servidor(gastos: _cuarentaYCinco, paginar: true));
      // Se deja también un aviso de «Cargar más» pendiente.
      await http.runWithClient(() => g.cargarMas(), () => _servidor(sinRed: true));
      expect(g.mensajeCargarMas.value, isNotEmpty);
      expect(g.gastos, hasLength(40));
      expect(archivoCaja('gastos_1').existsSync(), isTrue);

      await g.salir();

      // La caja de gastos ya no está abierta ni en el disco.
      expect(Hive.isBoxOpen('gastos_1'), isFalse);
      expect(archivoCaja('gastos_1').existsSync(), isFalse);
      expect(await Hive.boxExists('gastos_1'), isFalse);
      // Favoritos sigue intacta (abierta, en disco y con su contenido).
      expect(Hive.isBoxOpen('favoritos'), isTrue);
      expect(archivoCaja('favoritos').existsSync(), isTrue);
      expect(favoritos.get('lugar-1')?['nombre'], 'Mitad del Mundo');
      // Estado de vuelta al formulario, sin restos.
      expect(g.sesionActiva.value, isFalse);
      expect(g.gastos, isEmpty);
      expect(g.totalEnServidor.value, 0);
      expect(g.desdeCache.value, isFalse);
      expect(g.cargandoMas.value, isFalse);
      expect(g.mensajeCargarMas.value, isEmpty);
      expect(g.estado.value, EstadoCarga.exito);
      expect(g.hayMas, isFalse);
      expect(g.ultimaSincronizacion, 'desconocida');
    });

    test('salir con la copia local a la vista también la borra y quita el aviso', () async {
      final g = await entrar(_servidor(gastos: _dosGastos));
      await http.runWithClient(() => g.cargarGastos(), () => _servidor(sinRed: true));
      expect(g.desdeCache.value, isTrue);

      await g.salir();
      expect(g.desdeCache.value, isFalse);
      expect(g.gastos, isEmpty);
      expect(await Hive.boxExists('gastos_1'), isFalse);
    });

    test('cerrar sesión conserva el idioma guardado (caja ajustes, Paso 6)', () async {
      final ajustes = await Hive.openBox('ajustes');
      await ajustes.put('idioma', 'en');
      final g = await entrar(_servidor(gastos: _dosGastos));

      await g.salir();
      expect(await Hive.boxExists('gastos_1'), isFalse);
      expect(Hive.isBoxOpen('ajustes'), isTrue);
      expect(archivoCaja('ajustes').existsSync(), isTrue);
      expect(ajustes.get('idioma'), 'en');
    });

    test('después de salir, el token ya no se envía', () async {
      final g = await entrar(_servidor(gastos: _dosGastos));
      await g.salir();
      final peticiones = <_Peticion>[];
      await http.runWithClient(() => g.cargarGastos(), () => _servidor(peticiones: peticiones));
      // Sin token no hay petición: el servicio corta con un 401 local.
      expect(peticiones, isEmpty);
      expect(g.estado.value, EstadoCarga.error);
      expect(g.desdeCache.value, isFalse);
    });

    group('usuario A -> cerrar sesión -> usuario B', () {
      final gastosA = List.generate(
        20,
        (i) => <String, dynamic>{'id': 100 + i, 'descripcion': 'Gasto de A ${i + 1}', 'monto': 10 + i, 'categoria': 'comida', 'fecha': '2026-10-18'},
      );
      final usuarios = {
        'a@ejemplo.com': _Usuario(7, 'token-sintetico-a', gastosA, 45),
        'b@ejemplo.com': const _Usuario(8, 'token-sintetico-b', [], 0),
      };

      Future<GastosController> aYLuegoB({bool bSinRed = false}) async {
        final g = GastosController();
        await http.runWithClient(
            () => g.entrar('a@ejemplo.com', 'clave-1234'), () => _servidorMultiusuario(usuarios));
        expect(g.gastos, hasLength(20));
        expect(g.totalEnServidor.value, 45);
        expect(await Hive.boxExists('gastos_7'), isTrue);

        await g.salir();
        expect(await Hive.boxExists('gastos_7'), isFalse);

        await http.runWithClient(() => g.entrar('b@ejemplo.com', 'clave-1234'),
            () => _servidorMultiusuario(usuarios, sinRedAlListar: bSinRed));
        return g;
      }

      test('B ve solo lo suyo: lista vacía, total 0 y su propia caja', () async {
        final peticiones = <_Peticion>[];
        final g = await aYLuegoB();
        expect(g.sesionActiva.value, isTrue);
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
        await http.runWithClient(() => g.cargarGastos(),
            () => _servidorMultiusuario(usuarios, sinRedAlListar: true, peticiones: peticiones));
        expect(g.estado.value, EstadoCarga.exito);
        expect(g.desdeCache.value, isTrue);
        expect(g.gastos, isEmpty);
        expect(g.totalEnServidor.value, 0);
        // Y las peticiones de B llevan su token, no el de A.
        expect(peticiones.every((p) => p.cabeceras['authorization'] == 'Bearer token-sintetico-b'), isTrue);
      });

      test('si B entra sin red, ve el error: la copia de A ya no existe', () async {
        final g = await aYLuegoB(bSinRed: true);
        expect(g.sesionActiva.value, isTrue);
        expect(g.estado.value, EstadoCarga.error);
        expect(g.desdeCache.value, isFalse);
        expect(g.gastos, isEmpty);
        expect(g.totalEnServidor.value, 0);
        expect(g.mensajeError.value, startsWith('No hay conexión con el servidor'));
      });
    });
  });
}
