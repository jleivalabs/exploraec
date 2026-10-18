import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:exploraec/controllers/gastos_controller.dart';
import 'package:exploraec/controllers/places_controller.dart' show EstadoCarga;
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
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
    if (ruta == '/gastos/') {
      if (falloListar != null) return _json({'detail': 'x'}, falloListar);
      expect(req.headers['authorization'], 'Bearer $_token');
      return _json(gastos, 200, h: {'x-total-count': '${total ?? gastos.length}'});
    }
    return _json({'detail': 'no existe'}, 404);
  });
}

const _dosGastos = [
  {'id': 1, 'descripcion': 'Almuerzo', 'monto': 6.5, 'categoria': 'comida', 'fecha': '2026-10-05'},
  {'id': 2, 'descripcion': 'Taxi', 'monto': 3, 'categoria': 'transporte', 'fecha': '2026-10-05'},
];

void main() {
  setUp(() => Get.testMode = true);

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

  test('éxito: carga gastos y total desde X-Total-Count (monto entero o decimal)', () async {
    final g = await entrar(_servidor(gastos: _dosGastos));
    expect(g.gastos.length, 2);
    expect(g.totalEnServidor.value, 2);
    expect(g.gastos[1].monto, 3.0);
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

  test('sin conexión: error legible y la sesión no se pierde', () async {
    final g = await entrar(_servidor());
    await http.runWithClient(() => g.cargarGastos(), () => _servidor(sinRed: true));
    expect(g.estado.value, EstadoCarga.error);
    expect(g.mensajeError.value, startsWith('No hay conexión con el servidor'));
    expect(g.sesionActiva.value, isTrue);
  });

  test('401 al listar: vuelve al formulario y explica por qué', () async {
    final g = await entrar(_servidor());
    await http.runWithClient(() => g.cargarGastos(), () => _servidor(falloListar: 401));
    expect(g.sesionActiva.value, isFalse);
    expect(g.mensajeAuth.value, startsWith('Tu sesión caducó'));
  });

  test('5xx: mensaje genérico', () async {
    final g = await entrar(_servidor());
    await http.runWithClient(() => g.cargarGastos(), () => _servidor(falloListar: 503));
    expect(g.mensajeError.value, 'El servidor tuvo un problema. Inténtalo más tarde.');
  });

  // ---- Comprobaciones adicionales (Paso 7) ----

  group('Orden y formato de las peticiones', () {
    test('registro -> login -> listado, en ese orden y desde skip 0', () async {
      final peticiones = <_Peticion>[];
      await entrar(_servidor(gastos: _dosGastos, peticiones: peticiones));

      expect(peticiones.map((p) => '$p').toList(),
          ['POST /usuarios/', 'POST /usuarios/token', 'GET /gastos/']);
      expect(peticiones.last.query, {'skip': '0', 'limit': '20'});
    });

    test('registro en JSON, login en formulario y listado con Bearer', () async {
      final peticiones = <_Peticion>[];
      await entrar(_servidor(peticiones: peticiones));
      final registro = peticiones[0];
      final login = peticiones[1];
      final listado = peticiones[2];

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
      expect(registro.cabeceras.containsKey('authorization'), isFalse);
      expect(login.cabeceras.containsKey('authorization'), isFalse);
    });

    test('correo existente (400): no repite el registro y continúa al login', () async {
      final peticiones = <_Peticion>[];
      final g = await entrar(_servidor(registroDuplicado: true, peticiones: peticiones));
      expect(peticiones.map((p) => '$p').toList(),
          ['POST /usuarios/', 'POST /usuarios/token', 'GET /gastos/']);
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

    test('un fallo de recarga conserva los gastos ya cargados', () async {
      final g = await entrar(_servidor(gastos: _dosGastos));
      expect(g.gastos, hasLength(2));

      for (final fallo in [_servidor(sinRed: true), _servidor(falloListar: 503)]) {
        await http.runWithClient(() => g.cargarGastos(), () => fallo);
        expect(g.estado.value, EstadoCarga.error);
        expect(g.gastos.map((x) => x.descripcion).toList(), ['Almuerzo', 'Taxi']);
        expect(g.totalEnServidor.value, 2);
        expect(g.sesionActiva.value, isTrue);
      }

      // Al recuperarse, vuelve al estado de éxito con los datos del servidor.
      await http.runWithClient(() => g.cargarGastos(), () => _servidor(gastos: _dosGastos));
      expect(g.estado.value, EstadoCarga.exito);
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
}
