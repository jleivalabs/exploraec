import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';

/// Servidor falso del backend de gastos para las pruebas — Sesión 8. Se
/// conecta a `dio` como `HttpClientAdapter`: ninguna petición sale de la
/// máquina. Imita el contrato real (login con formulario, `/usuarios/me`,
/// `/gastos/` con `skip`/`limit` y `X-Total-Count`, errores con `detail`) y
/// deja provocar fallos, retener respuestas y revisar cada petición.
///
/// Tokens y contraseñas son sintéticos; las pruebas no los imprimen.
class ServidorGastosFalso implements HttpClientAdapter {
  ServidorGastosFalso([Map<String, UsuarioFalso>? usuarios]) : usuarios = usuarios ?? {};

  /// Correo → usuario.
  final Map<String, UsuarioFalso> usuarios;

  /// Cada petición recibida, en orden.
  final peticiones = <PeticionFalsa>[];

  /// Todas las peticiones fallan como sin conexión.
  bool sinRed = false;

  /// Solo `GET /gastos/` falla como sin conexión / tiempo agotado.
  bool sinRedAlListar = false;
  bool timeoutAlListar = false;

  /// `GET /gastos/` respeta `skip`/`limit`; `solapar` repite gastos ya
  /// enviados (como si entrara uno nuevo entre una página y otra).
  bool paginar = false;
  int solapar = 0;

  /// Códigos HTTP de error forzados por endpoint.
  int? falloRegistro;
  int? falloLogin;
  int? falloPerfil;
  int? falloListar;
  int? falloCategorias;

  /// Retienen la respuesta hasta que la prueba complete el `Completer`; el
  /// `...Recibido` correspondiente avisa que la petición ya llegó.
  Completer<void>? retenerLogin;
  Completer<void>? retenerPerfil;
  Completer<void> perfilRecibido = Completer<void>();
  Completer<void>? retenerListado;
  Completer<void> listadoRecibido = Completer<void>();

  /// Un `Dio` que usa este servidor.
  Dio crearDio() => Dio(BaseOptions(baseUrl: 'http://servidor-falso'))..httpClientAdapter = this;

  /// Peticiones como 'GET /ruta'.
  List<String> get rutas => peticiones.map((p) => '$p').toList();

  /// `skip`/`limit` de cada `GET /gastos/`, como texto.
  List<Map<String, String>> get consultasDeListado => peticiones
      .where((p) => p.ruta == '/gastos/' && p.metodo == 'GET')
      .map((p) => p.query.map((k, v) => MapEntry(k, '$v')))
      .toList();

  ResponseBody _json(Object? cuerpo, int codigo, [Map<String, List<String>> h = const {}]) =>
      ResponseBody.fromString(cuerpo == null ? '' : jsonEncode(cuerpo), codigo,
          headers: {Headers.contentTypeHeader: ['application/json'], ...h});

  @override
  Future<ResponseBody> fetch(
      RequestOptions o, Stream<Uint8List>? cuerpo, Future<void>? cancelar) async {
    final texto =
        cuerpo == null ? '' : utf8.decode((await cuerpo.toList()).expand((x) => x).toList());
    final peticion = PeticionFalsa(o.method, o.path, Map.of(o.queryParameters),
        Map.of(o.headers), texto, '${o.contentType ?? o.headers[Headers.contentTypeHeader] ?? ''}');
    peticiones.add(peticion);
    if (sinRed) throw const SocketException('sin red');
    final ruta = o.path;

    if (ruta == '/usuarios/' && o.method == 'POST') {
      if (falloRegistro != null) return _json({'detail': 'x'}, falloRegistro!);
      final b = jsonDecode(texto) as Map;
      final correo = b['email'] as String;
      final clave = b['password'] as String;
      if (clave.length < 8) {
        return _json({
          'detail': [
            {'type': 'string_too_short', 'loc': ['body', 'password'], 'msg': 'String should have at least 8 characters'}
          ]
        }, 422);
      }
      if (usuarios.containsKey(correo)) {
        return _json({'detail': 'El email $correo ya está registrado'}, 400);
      }
      final id = usuarios.values.fold<int>(0, (m, u) => u.id > m ? u.id : m) + 1;
      usuarios[correo] = UsuarioFalso(id: id, password: clave);
      return _json({'id': id, 'email': correo}, 201);
    }

    if (ruta == '/usuarios/token') {
      if (retenerLogin != null) await retenerLogin!.future;
      if (!peticion.tipoContenido.contains('application/x-www-form-urlencoded')) {
        return _json({
          'detail': [
            {'type': 'missing', 'loc': ['body', 'username'], 'msg': 'Field required'}
          ]
        }, 422);
      }
      if (falloLogin != null) return _json({'detail': 'x'}, falloLogin!);
      final campos = Uri.splitQueryString(texto);
      final u = usuarios[campos['username']];
      if (u == null || u.password != campos['password']) {
        return _json({'detail': 'Email o contraseña incorrectos'}, 401);
      }
      return _json({'access_token': u.token, 'token_type': 'bearer'}, 200);
    }

    // Desde aquí todo exige un token válido: se identifica al usuario por él.
    final correo = usuarios.entries
        .where((e) => peticion.autorizacion == 'Bearer ${e.value.token}')
        .map((e) => e.key)
        .firstOrNull;
    if (correo == null) {
      return _json({
        'detail': peticion.autorizacion == null ? 'Not authenticated' : 'No se pudo validar las credenciales'
      }, 401);
    }
    final usuario = usuarios[correo]!;

    if (ruta == '/usuarios/me') {
      if (!perfilRecibido.isCompleted) perfilRecibido.complete();
      if (retenerPerfil != null) await retenerPerfil!.future;
      if (falloPerfil != null) return _json({'detail': 'x'}, falloPerfil!);
      return _json({'id': usuario.id, 'email': correo}, 200);
    }
    if (ruta == '/gastos/categorias') {
      if (falloCategorias != null) return _json({'detail': 'x'}, falloCategorias!);
      return _json({'categorias': ['comida', 'transporte', 'entretenimiento', 'otros'], 'limite_por_categoria': 500.0}, 200);
    }
    if (ruta == '/gastos/' && o.method == 'GET') {
      // La respuesta se arma con los datos del usuario del token, aunque se
      // entregue más tarde (así se prueban las respuestas tardías).
      final gastos = List<Map<String, dynamic>>.of(usuario.gastos);
      final total = usuario.total ?? gastos.length;
      if (!listadoRecibido.isCompleted) listadoRecibido.complete();
      if (retenerListado != null) await retenerListado!.future;
      if (sinRedAlListar) throw const SocketException('sin red');
      if (timeoutAlListar) {
        throw DioException(requestOptions: o, type: DioExceptionType.receiveTimeout);
      }
      if (falloListar != null) return _json({'detail': 'x'}, falloListar!);
      var pagina = gastos;
      if (paginar) {
        final skip = int.parse('${o.queryParameters['skip'] ?? 0}');
        final limit = int.parse('${o.queryParameters['limit'] ?? 20}');
        final desde = (skip - solapar).clamp(0, gastos.length);
        pagina = gastos.sublist(desde, (desde + limit).clamp(0, gastos.length));
      }
      return _json(pagina, 200, {'x-total-count': ['$total']});
    }
    if (ruta == '/gastos/' && o.method == 'POST') {
      // Como el backend: máximo 500 por categoría y por usuario.
      final b = jsonDecode(texto) as Map<String, dynamic>;
      final acumulado = usuario.gastos
          .where((g) => g['categoria'] == b['categoria'])
          .fold<double>(0, (suma, g) => suma + (g['monto'] as num));
      if (acumulado + (b['monto'] as num) > 500) {
        return _json({'detail': "Este gasto supera el límite de 500.0 para la categoría '${b['categoria']}'"}, 400);
      }
      final id = usuario.gastos.fold<int>(0, (m, g) => (g['id'] as int) > m ? g['id'] as int : m) + 1;
      final nuevo = {'id': id, 'fecha': '2026-10-18', ...b};
      usuario.gastos.add(nuevo);
      if (usuario.total != null) usuario.total = usuario.total! + 1;
      return _json(nuevo, 201);
    }
    final m = RegExp(r'^/gastos/(\d+)$').firstMatch(ruta);
    if (m != null && (o.method == 'PATCH' || o.method == 'DELETE')) {
      final id = int.parse(m.group(1)!);
      final i = usuario.gastos.indexWhere((g) => g['id'] == id);
      if (i < 0) return _json({'detail': 'El gasto $id no existe'}, 404);
      if (o.method == 'PATCH') {
        usuario.gastos[i] = {...usuario.gastos[i], ...jsonDecode(texto) as Map<String, dynamic>};
        return _json(usuario.gastos[i], 200);
      }
      usuario.gastos.removeAt(i);
      if (usuario.total != null) usuario.total = usuario.total! - 1;
      return ResponseBody.fromString('', 204); // sin cuerpo, como el backend
    }
    return _json({'detail': 'ruta no prevista en la prueba: $ruta'}, 404);
  }

  @override
  void close({bool force = false}) {}
}

/// Un usuario del servidor falso. El token es sintético y depende del id.
class UsuarioFalso {
  UsuarioFalso({required this.id, required this.password, List<Map<String, dynamic>>? gastos, this.total})
      : gastos = gastos ?? [];

  final int id;
  final String password;
  List<Map<String, dynamic>> gastos;

  /// `X-Total-Count`; si es null, el largo de [gastos].
  int? total;

  String get token => 'token-sintetico-$id';
}

/// Una petición recibida por el servidor falso.
class PeticionFalsa {
  PeticionFalsa(this.metodo, this.ruta, this.query, this.cabeceras, this.cuerpo, this.tipoContenido);

  final String metodo;
  final String ruta;
  final Map<String, dynamic> query;
  final Map<String, dynamic> cabeceras;
  final String cuerpo;
  final String tipoContenido;

  String? get autorizacion => cabeceras['Authorization'] as String?;

  @override
  String toString() => '$metodo $ruta';
}
