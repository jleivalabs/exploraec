import 'package:get/get.dart';

import '../models/gasto.dart';
import '../models/usuario.dart';
import '../repositories/gastos_repository.dart';
import '../services/api_client.dart';
import '../services/gastos_api_service.dart';
import 'auth_controller.dart';
import 'places_controller.dart' show EstadoCarga;

/// Estado de la sección Gastos (patrón de la Sesión 4: el controller guarda
/// el estado y `Obx` reconstruye la pantalla). Reutiliza `EstadoCarga`; el
/// "vacío" se deriva de `gastos.isEmpty` con estado `exito`. Desde la
/// Sesión 7 los gastos pasan por `GastosRepository` (servidor primero,
/// caché de Hive como respaldo). Desde la Sesión 8 la sesión la maneja
/// `AuthController` y aquí se agrega el CRUD completo.
class GastosController extends GetxController {
  /// [repositorio] es opcional (por defecto, el de Hive sobre `ApiClient`).
  GastosController({GastosRepository? repositorio}) : _repositorioInyectado = repositorio;

  static const int _tamanoPagina = 20;

  final AuthController _auth = Get.find<AuthController>();
  late final GastosApiService _api = GastosApiService(Get.find<ApiClient>());
  final GastosRepository? _repositorioInyectado;
  late final GastosRepository _repository = _repositorioInyectado ?? GastosRepository(_api);

  final RxList<Gasto> gastos = <Gasto>[].obs;
  final Rx<EstadoCarga> estado = EstadoCarga.exito.obs;
  final RxString mensajeError = ''.obs;
  final RxInt totalEnServidor = 0.obs;

  /// Categorías que define el backend (`GET /gastos/categorias`).
  final RxList<String> categorias = <String>[].obs;

  /// `true` solo cuando la última carga exitosa vino de la caché local (el
  /// servidor no respondió): la UI lo usa para avisar «datos guardados».
  /// `totalEnServidor` conserva entonces el total que el servidor informó
  /// en la última sincronización (un metadato: la copia puede ser parcial).
  final RxBool desdeCache = false.obs;
  String get ultimaSincronizacion => _repository.ultimaSincronizacion;

  /// «Cargar más» en curso: evita pedir la misma página dos veces.
  final RxBool cargandoMas = false.obs;

  /// Motivo del último fallo de «Cargar más» (vacío si no hubo). La lista
  /// lo muestra junto al botón, sin tapar lo que ya se cargó.
  final RxString mensajeCargarMas = ''.obs;

  /// Con la copia local a la vista no se pide la página siguiente: el
  /// servidor no responde y el desplazamiento no sería coherente.
  bool get hayMas => !desdeCache.value && gastos.length < totalEnServidor.value;

  /// Vigencia (Sesión 8): cambia al iniciar la carga de una sesión y al
  /// limpiar. Cada operación recuerda el valor con que empezó; si al volver
  /// del servidor ya no coincide, su respuesta es de otra sesión y no toca
  /// lista, errores, indicadores de carga ni caché.
  int _sesion = 0;
  bool _vigente(int sesion) => sesion == _sesion;

  late final Worker _alCambiarUsuario;
  Future<void>? _inicio;

  /// Carga inicial de la sesión en curso (o `null` si no hubo ninguna): la
  /// dispara el cambio de `usuario`; quien necesite esperarla puede hacerlo.
  Future<void>? get cargaInicial => _inicio;

  @override
  void onInit() {
    super.onInit();
    // Cuando `AuthController` deja un usuario (login, registro o sesión
    // restaurada), se cargan sus datos. Si ya hay uno, se cargan de una vez.
    // El worker se guarda para liberarlo en `onClose()`.
    _alCambiarUsuario = ever<Usuario?>(_auth.usuario, (u) {
      if (u != null) _inicio = iniciar();
    });
    if (_auth.estaAutenticado) _inicio = iniciar();
  }

  @override
  void onClose() {
    _alCambiarUsuario.dispose();
    super.onClose();
  }

  /// Abre la caja del usuario, pide las categorías y carga sus gastos. Lo
  /// anterior en memoria se descarta primero: otra persona nunca ve, ni por
  /// un instante, la lista de la sesión previa.
  Future<void> iniciar() async {
    final usuario = _auth.usuario.value;
    if (usuario == null) return;
    final sesion = ++_sesion;
    _vaciarEstado();
    estado.value = EstadoCarga.cargando;
    try {
      final abierta = await _repository.abrirParaUsuario(usuario.id);
      if (!abierta || !_vigente(sesion)) return;
    } on ApiException catch (e) {
      if (!_vigente(sesion)) return;
      mensajeError.value = e.mensaje;
      estado.value = EstadoCarga.error;
      return;
    } catch (e) {
      if (!_vigente(sesion)) return;
      mensajeError.value = 'No se pudo preparar tu copia local: $e';
      estado.value = EstadoCarga.error;
      return;
    }
    await cargarGastos();
  }

  Future<void> cargarGastos() async {
    if (!_auth.estaAutenticado) return;
    final sesion = _sesion;
    estado.value = EstadoCarga.cargando;
    // Paso 5: las categorías se piden (si faltan) antes de la lista, pero su
    // fallo no bloquea la lista ni la copia local: el formulario las vuelve
    // a necesitar y se reintentan en la próxima recarga.
    if (categorias.isEmpty) {
      try {
        await cargarCategorias();
      } on ApiException {
        // Sin categorías no se puede crear, pero sí ver los gastos.
      }
      if (!_vigente(sesion)) return;
    }

    // Por qué: el bloque traduce el resultado -o la excepción- a los mismos 3
    // estados de siempre. Desde la Sesión 8 un 401 lo resuelve
    // `AuthController` (interceptor del Paso 7), no este controller.
    try {
      // TODO(sesion-07): borra el bloque de abajo (desde `final resultado` hasta `estado.value = EstadoCarga.exito;`) y descomenta el bloque completo. (Paso 2 — repositorio con caché)
      // Por qué: llamar al servicio directo, como en la Sesión 6, hacía que
      // sin red la carga fallara sin más. Ahora los gastos se piden al
      // repositorio, que primero intenta el servidor y, si falla por red o
      // por el propio servidor, devuelve la última copia guardada en Hive
      // (y `desdeCache` pasa a `true` para que la pantalla lo avise).
      // Ajuste propio respecto al starter: se piden 20 por página (no 100) y
      // `totalEnServidor` es el total de `X-Total-Count` (o el guardado con
      // la copia), no `lista.length`: así siguen funcionando «Cargar más» y
      // el aviso de copia parcial.
      await _refrescar();
      if (_vigente(sesion)) estado.value = EstadoCarga.exito;
    } on ApiException catch (e) {
      if (!_vigente(sesion)) return;
      desdeCache.value = false;
      mensajeError.value = e.mensaje;
      estado.value = EstadoCarga.error;
    } catch (e) {
      if (!_vigente(sesion)) return;
      desdeCache.value = false;
      mensajeError.value = 'Error inesperado: $e';
      estado.value = EstadoCarga.error;
    }
  }

  /// Vuelve a pedir la primera página al repositorio sin pasar por
  /// «cargando»: se usa también después de crear, editar o eliminar para que
  /// la pantalla no parpadee (y la copia de Hive se reemplace).
  Future<void> _refrescar() async {
    final sesion = _sesion;
    final r = await _repository.obtenerGastos(limit: _tamanoPagina);
    if (!_vigente(sesion)) return;
    gastos.value = r.gastos;
    totalEnServidor.value = r.total;
    desdeCache.value = r.desdeCache;
    mensajeCargarMas.value = '';
  }

  /// Siguiente página (skip = lo ya cargado), también a través del
  /// repositorio para que la copia local crezca con cada página descargada.
  /// No cambia `estado`: si falla, lo ya mostrado se conserva tal cual y el
  /// motivo queda en `mensajeCargarMas` (la lista lo muestra junto al botón,
  /// que sirve para reintentar). Sin respaldo: devolver la copia aquí sería
  /// presentar la primera página como si fuera la siguiente.
  Future<void> cargarMas() async {
    if (!hayMas || cargandoMas.value) return;
    final sesion = _sesion;
    cargandoMas.value = true;
    mensajeCargarMas.value = '';
    try {
      final r = await _repository.obtenerSiguientePagina(gastos, limit: _tamanoPagina);
      if (!_vigente(sesion)) return;
      gastos.addAll(r.nuevos);
      totalEnServidor.value = r.total;
    } on ApiException catch (e) {
      if (_vigente(sesion)) mensajeCargarMas.value = e.mensaje;
    } catch (e) {
      if (_vigente(sesion)) mensajeCargarMas.value = 'Error inesperado: $e';
    } finally {
      if (_vigente(sesion)) cargandoMas.value = false;
    }
  }

  Future<void> cargarCategorias() async {
    // Por qué: las categorías (y el límite de 500) las decide el servidor; la
    // app solo las muestra. Si mañana el backend agrega una, aparece sola.
    // Ajuste de integración: la respuesta solo se usa si la sesión no cambió.
    // TODO(sesion-08) Paso 5: descomenta las 3 líneas de abajo (categorías).
    final sesion = _sesion;
    final r = await _api.listarCategorias();
    if (_vigente(sesion)) categorias.assignAll(r.categorias);
  }

  /// Crea un gasto. Si el servidor lo rechaza (por ejemplo, el límite de 500),
  /// lanza `ApiException` con el mensaje para que el formulario lo muestre.
  Future<void> crear(String descripcion, double monto, String categoria) async {
    // Por qué: se manda el gasto al servidor y la pantalla se actualiza con lo
    // que el servidor guardó realmente (no se supone que salió bien).
    // TODO(sesion-08) Paso 5: descomenta las 2 líneas de abajo (crear).
    // Integración: si el servidor rechaza el gasto, la excepción sube al
    // formulario. Si lo acepta, un fallo al recargar ya NO es un fallo al
    // crear (reintentar duplicaría el gasto): se muestra en la lista.
    await _api.crear({'descripcion': descripcion, 'monto': monto, 'categoria': categoria});
    await _recargarTrasCambio();
  }

  /// Recarga la primera página (y reemplaza la copia) después de un cambio que
  /// el servidor ya aceptó. Sus errores van al estado de la lista, no a quien
  /// hizo el cambio.
  Future<void> _recargarTrasCambio() async {
    final sesion = _sesion;
    try {
      await _refrescar();
      if (_vigente(sesion)) estado.value = EstadoCarga.exito;
    } on ApiException catch (e) {
      if (!_vigente(sesion)) return;
      desdeCache.value = false;
      mensajeError.value = e.mensaje;
      estado.value = EstadoCarga.error;
    }
  }

  /// Edita un gasto enviando SOLO los campos que cambiaron.
  Future<void> actualizar(int id, Map<String, dynamic> cambios) async {
    // Por qué: PATCH modifica solo lo que se envía. Si el gasto ya no existe
    // (404), se refresca la lista para que desaparezca de la pantalla.
    // TODO(sesion-08) Paso 6: descomenta las 7 líneas de abajo (editar).
    // Integración: igual que `crear`, la recarga posterior no convierte un
    // cambio aceptado en un error, ni tapa el mensaje del 404.
    try {
      await _api.actualizar(id, cambios);
    } on ApiException catch (e) {
      if (e.statusCode == 404) await _recargarTrasCambio();
      rethrow;
    }
    await _recargarTrasCambio();
  }

  Future<void> eliminar(int id) async {
    // Por qué: mismo patrón que editar. El servidor responde 204 (sin cuerpo)
    // y la lista se vuelve a pedir, así la caché de Hive también se actualiza.
    // TODO(sesion-08) Paso 6: descomenta las 7 líneas de abajo (eliminar).
    try {
      await _api.eliminar(id);
    } on ApiException catch (e) {
      if (e.statusCode == 404) await _recargarTrasCambio();
      rethrow;
    }
    await _recargarTrasCambio();
  }

  /// Borra todo lo de la persona que cierra sesión — la lista en pantalla y su
  /// caja de Hive (`GastosRepository.vaciar`, Sesión 7). Lo llama
  /// `AuthController.cerrarSesion`. Primero invalida las operaciones
  /// pendientes y limpia la memoria (eso no puede fallar); después borra el
  /// disco. Si el borrado falla, el error sube a quien llamó: no se oculta.
  /// Devuelve `true` si había una caja abierta y se borró.
  Future<bool> limpiar() async {
    _sesion++;
    _inicio = null;
    _vaciarEstado();
    categorias.clear();
    return _repository.vaciar();
  }

  void _vaciarEstado() {
    gastos.clear();
    totalEnServidor.value = 0;
    desdeCache.value = false;
    cargandoMas.value = false;
    mensajeCargarMas.value = '';
    mensajeError.value = '';
    estado.value = EstadoCarga.exito;
  }
}
