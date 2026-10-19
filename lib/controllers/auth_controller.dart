import 'package:get/get.dart';

import '../models/usuario.dart';
import '../services/api_client.dart';
import '../repositories/gastos_repository.dart';
import '../services/secure_token_storage.dart';
import '../services/settings_service.dart';
import 'gastos_controller.dart';

/// Estado de la sesión de toda la app — Sesión 8 (mismo patrón de GetX de las
/// Sesiones 4-7: el controller guarda el estado y `Obx` reconstruye la
/// pantalla). `usuario` es null cuando no hay sesión.
class AuthController extends GetxController {
  AuthController({ApiClient? api, SecureTokenStorage? almacen})
      : _api = api ?? Get.find<ApiClient>(),
        _almacen = almacen ?? SecureTokenStorage();

  final ApiClient _api;
  final SecureTokenStorage _almacen;

  final Rxn<Usuario> usuario = Rxn<Usuario>();
  final RxBool cargando = false.obs;

  /// `true` mientras se comprueba el token guardado al abrir la app.
  final RxBool restaurando = false.obs;

  /// Error del último intento de registro o inicio de sesión.
  final RxString mensajeError = ''.obs;

  /// Aviso que se muestra donde pide iniciar sesión (por ejemplo, «caducó»,
  /// o que algo no se pudo borrar al cerrar sesión).
  final RxString avisoSesion = ''.obs;

  bool get estaAutenticado => usuario.value != null;

  /// Marca de sesión (Sesión 9): cambia cada vez que se abre o se cierra una
  /// sesión. Quien empieza una operación larga la guarda y, al volver, la
  /// compara: si cambió, el resultado es de otra sesión (aunque sea la misma
  /// persona que salió y volvió a entrar) y se descarta.
  int _marca = 0;
  int get marcaSesion => _marca;

  /// Cierre de sesión en curso: una segunda llamada (por ejemplo, el menú y
  /// un 401 a la vez) espera a la misma en vez de repetir el borrado.
  Future<bool>? _cerrando;

  /// Vigencia de la restauración (Paso 4): cambia al iniciar o cerrar sesión.
  /// Una restauración que vuelve del servidor después de eso no abre nada.
  int _restauracion = 0;
  Future<void>? _restaurandoFuturo;

  /// La restauración lanzada al crear el controller (para quien deba esperarla).
  Future<void>? get restauracion => _restaurandoFuturo;

  @override
  void onInit() {
    super.onInit();
    _api.alSesionCaducada = sesionCaducada;
    _restaurandoFuturo = restaurarSesion();
  }

  /// POST /usuarios/ con JSON y, si sale bien (201), inicia sesión.
  /// Correo repetido → 400 con el motivo en `detail`.
  Future<void> registrar(String email, String password) async {
    // Por qué: crear la cuenta y entrar son dos peticiones seguidas; `await`
    // permite escribirlas en orden. Un error del servidor se muestra tal cual.
    // TODO(sesion-08) Paso 3: descomenta las 10 líneas de abajo (registrar).
    // Integración: tras crear la cuenta se reutiliza `iniciarSesion` (login
    // «todo o nada» y vigencia de la sesión ya resueltos ahí).
    cargando.value = true;
    mensajeError.value = '';
    try {
      await _api.post('/usuarios/', data: {'email': email, 'password': password});
      await iniciarSesion(email, password);
    } on ApiException catch (e) {
      mensajeError.value = e.mensaje;
    } finally {
      cargando.value = false;
    }
  }

  /// POST /usuarios/token — OJO: `application/x-www-form-urlencoded`, no JSON.
  /// El campo se llama `username` pero lleva el correo.
  Future<void> iniciarSesion(String email, String password) async {
    // Por qué: el endpoint de login sigue el estándar OAuth2 y exige un
    // formulario, no JSON; mandar JSON devuelve 422. El token recibido se
    // guarda en memoria (para el interceptor) y en el almacenamiento seguro.
    // TODO(sesion-08) Paso 2: descomenta las 18 líneas de abajo (iniciar sesión).
    // Ajuste propio (ver PLACEHOLDERS.md): la sesión se abre «todo o nada».
    // `usuario` se asigna al final, cuando el token ya está guardado; si
    // `/usuarios/me` o el almacenamiento seguro fallan, el token no queda ni
    // en memoria ni guardado.
    cargando.value = true;
    mensajeError.value = '';
    _restauracion++; // una restauración aún en curso ya no cuenta
    restaurando.value = false;
    var tokenAsignado = false;
    try {
      final r = await _api.post(
        '/usuarios/token',
        data: {'username': email, 'password': password},
        options: Options(contentType: Headers.formUrlEncodedContentType),
      );
      final token = (r.data as Map)['access_token'] as String;
      _api.token = token;
      tokenAsignado = true;
      final yo = await _leerUsuario();
      await _almacen.guardar(token);
      _marca++;
      usuario.value = yo;
      avisoSesion.value = '';
      await _recordarUsuario(yo.id);
    } on ApiException catch (e) {
      mensajeError.value = e.mensaje;
      if (tokenAsignado) await _descartarTokenDeLoginFallido();
    } catch (e) {
      mensajeError.value = 'No se pudo iniciar sesión: $e';
      if (tokenAsignado) await _descartarTokenDeLoginFallido();
    } finally {
      cargando.value = false;
    }
  }

  /// Al abrir la app: si hay un token guardado, comprueba con el servidor que
  /// siga siendo válido (GET /usuarios/me) y deja la sesión abierta.
  Future<void> restaurarSesion() async {
    // Por qué: sin esto la sesión se perdería en cada arranque. Un 401 quiere
    // decir que el token caducó: se borra y se pide iniciar sesión. Otro error
    // (sin conexión) no borra nada: el token puede seguir siendo válido.
    // TODO(sesion-08) Paso 4: descomenta las 16 líneas de abajo (restaurar sesión).
    // Integración: cada `await` comprueba que la restauración siga vigente
    // (no se cerró ni se inició otra sesión entretanto); `usuario` se asigna
    // solo con el usuario ya confirmado; sin conexión el token sigue guardado
    // pero no queda en memoria ni da la sesión por abierta.
    final intento = ++_restauracion;
    restaurando.value = true;
    try {
      final guardado = await _almacen.leer();
      if (guardado == null || intento != _restauracion) return;
      _api.token = guardado;
      final yo = await _leerUsuario();
      if (intento != _restauracion) return;
      _marca++;
      usuario.value = yo;
      await _recordarUsuario(yo.id);
    } on ApiException catch (e) {
      if (intento != _restauracion) return;
      if (e.statusCode == 401) {
        final todoBorrado = await cerrarSesion();
        avisoSesion.value = todoBorrado
            ? 'Tu sesión caducó, inicia sesión de nuevo.'
            : 'Tu sesión caducó. ${avisoSesion.value}';
      } else {
        _api.token = null;
        avisoSesion.value = e.mensaje;
      }
    } catch (e) {
      if (intento != _restauracion) return;
      _api.token = null;
      avisoSesion.value = 'No se pudo recuperar la sesión guardada: $e';
    } finally {
      if (intento == _restauracion) restaurando.value = false;
    }
  }

  Future<void>? _caducando;

  /// Cierre por caducidad en curso (para quien deba esperarlo).
  Future<void>? get cierrePorCaducidad => _caducando;

  /// Lo llama el interceptor cuando el servidor responde 401 (token vencido).
  /// Varios 401 a la vez comparten un solo cierre, aviso y navegación.
  Future<void> sesionCaducada() =>
      _caducando ??= _caducar().whenComplete(() => _caducando = null);

  Future<void> _caducar() async {
    final todoBorrado = await cerrarSesion();
    avisoSesion.value = todoBorrado
        ? 'Tu sesión caducó, inicia sesión de nuevo.'
        : 'Tu sesión caducó. ${avisoSesion.value}';
    // Si había una pantalla encima (por ejemplo, el formulario), se vuelve a la base.
    if (Get.key.currentState != null) Get.until((ruta) => ruta.isFirst);
  }

  /// Cierra la sesión: olvida el token (en memoria y en el almacenamiento
  /// seguro) y los gastos de la persona (lista en pantalla y su caja de Hive).
  /// Devuelve `true` solo si todo se borró; si algo falló, la sesión queda
  /// cerrada igualmente y `avisoSesion` dice qué no se pudo borrar.
  Future<bool> cerrarSesion() => _cerrando ??= _cerrar().whenComplete(() => _cerrando = null);

  Future<bool> _cerrar() async {
    // Primero lo que vive en memoria, sin esperar al disco: desde aquí ninguna
    // petición lleva el token y la pantalla vuelve a «sin sesión».
    _restauracion++; // una restauración en curso ya no abrirá la sesión
    _marca++;
    restaurando.value = false;
    _api.token = null;
    usuario.value = null;

    final fallos = <String>[];
    // Por qué: el token solo es una parte de lo que identifica a la persona.
    // Su copia de gastos (la caja de Hive de la Sesión 7) y la lista en
    // pantalla también deben borrarse, o la siguiente persona que use este
    // teléfono las vería.
    // TODO(sesion-08) Paso 8: descomenta la línea de abajo (limpiar los gastos).
    // Adelantado al Paso 2 (ver PLACEHOLDERS.md) para no perder el borrado de
    // la Sesión 7. `isPrepared` es `true` mientras el `lazyPut` aún no creó el
    // controller: entonces no hay lista ni caja abierta, y crearlo aquí solo
    // para limpiarlo dispararía su carga inicial.
    var cacheBorrada = true;
    var cajaBorradaPorElController = false;
    if (Get.isRegistered<GastosController>() && !Get.isPrepared<GastosController>()) {
      try {
        cajaBorradaPorElController = await Get.find<GastosController>().limpiar();
      } catch (_) {
        cacheBorrada = false;
      }
    }
    // Paso 4: la caja del último usuario confirmado, aunque ningún controller
    // la haya abierto (sesión restaurada que resultó caducada). Solo esa caja:
    // favoritos e idioma no se tocan. El id se olvida solo si el borrado
    // funcionó, para poder reintentarlo en el próximo cierre. Si el controller
    // ya borró la caja abierta (la de este mismo usuario), no se repite.
    final ultimoId = SettingsService.ultimoUsuarioId;
    if (ultimoId != null) {
      try {
        if (!cajaBorradaPorElController) await GastosRepository.borrarCajaDeUsuario(ultimoId);
        await SettingsService.olvidarUltimoUsuario();
        cacheBorrada = true;
      } catch (_) {
        cacheBorrada = false;
      }
    }
    if (!cacheBorrada) fallos.add('tus gastos guardados');
    // Se intenta aunque haya fallado lo anterior: cada borrado es independiente.
    try {
      await _almacen.borrar();
    } catch (_) {
      fallos.add('el token guardado');
    }

    if (fallos.isEmpty) return true;
    avisoSesion.value = 'Cerraste sesión, pero no se pudo borrar de este teléfono: '
        '${fallos.join(' ni ')}. Vuelve a intentarlo iniciando y cerrando sesión.';
    return false;
  }

  /// PUT /usuarios/me/password — responde 204 (sin cuerpo). Si sale bien, cierra
  /// la sesión para entrar con la contraseña nueva.
  Future<void> cambiarPassword(String actual, String nueva) async {
    // Por qué: un 204 no trae cuerpo, así que no hay nada que leer de la
    // respuesta. Con la contraseña actual equivocada el servidor responde con
    // un error y su mensaje se muestra tal cual.
    // TODO(sesion-08) OPCIONAL Paso 9: descomenta las 10 líneas de abajo (cambiar contraseña).
    // cargando.value = true;
    // mensajeError.value = '';
    // try {
    //   await _api.put('/usuarios/me/password', data: {'password_actual': actual, 'password_nueva': nueva});
    //   await cerrarSesion();
    // } on ApiException catch (e) {
    //   mensajeError.value = e.mensaje;
    // } finally {
    //   cargando.value = false;
    // }
  }

  /// GET /usuarios/me → deja el usuario de la sesión en `usuario`.
  Future<void> cargarUsuario() async {
    usuario.value = await _leerUsuario();
  }

  Future<Usuario> _leerUsuario() async {
    final r = await _api.get('/usuarios/me');
    return Usuario.fromJson(Map<String, dynamic>.from(r.data as Map));
  }

  /// Metadato de limpieza (ver `SettingsService.ultimoUsuarioId`). Si no se
  /// puede guardar, la sesión sigue abierta: solo se pierde ese respaldo.
  Future<void> _recordarUsuario(int id) async {
    try {
      await SettingsService.recordarUltimoUsuario(id);
    } catch (_) {}
  }

  /// Un login que no terminó no deja el token en memoria ni guardado.
  Future<void> _descartarTokenDeLoginFallido() async {
    _api.token = null;
    try {
      await _almacen.borrar();
    } catch (_) {
      mensajeError.value = '${mensajeError.value} (Además, no se pudo borrar el token guardado.)';
    }
  }

  /// Solo práctica (Paso 7): la siguiente petición responderá 401.
  void invalidarTokenParaPruebas() => _api.token = 'token-invalido';
}
