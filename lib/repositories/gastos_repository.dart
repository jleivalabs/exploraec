import 'package:hive/hive.dart';

import '../models/gasto.dart';
import '../services/api_exception.dart';
import '../services/gastos_api_service.dart';

/// Decide de dónde salen los gastos — Sesión 7. Quien lo usa (el
/// controller) pide «mis gastos» sin saber si vinieron del backend o de la
/// copia local: primero intenta el servidor y, solo si falla por red o por
/// el propio servidor, devuelve la última copia guardada en Hive.
///
/// Decisiones (se pueden justificar en clase):
/// - Cada usuario tiene su propia caja, `gastos_<id>`: los gastos son datos
///   personales y Hive guarda **sin cifrar** en el almacenamiento de la app.
/// - La caja se borra al cerrar sesión (`vaciar`).
/// - Un 401 (sesión caducada) o un 400/403/404 **no** usan la caché: no son
///   fallas de infraestructura y esconderlas con datos viejos confundiría.
/// - La caché es de **lectura**: un gasto creado sin red no existe en el
///   servidor (se retoma en la Sesión 8).
/// - El token **no** se guarda aquí: desde la Sesión 8 va en el
///   almacenamiento seguro (`SecureTokenStorage`).
///
/// Ajuste propio respecto al starter: se conserva la paginación de la
/// Sesión 6 (páginas de `limit` elementos y el total de `X-Total-Count`).
/// La copia guarda exactamente lo que el usuario tiene a la vista —la
/// primera página y las que fue sumando con «Cargar más»— junto con el
/// total que informó el servidor, así una copia parcial se reconoce como
/// tal (por ejemplo, 40 guardados de 45).
///
/// Sesión 8 — vigencia: cada operación recuerda la caja y la «época» en que
/// empezó (`_Contexto`). Si mientras esperaba al servidor se cerró la sesión o
/// se abrió la caja de otra persona, su respuesta ya no se escribe ni se lee
/// en ninguna caja: nunca se usa la que casualmente esté en `_caja` al final.
class GastosRepository {
  GastosRepository(this._api);

  final GastosApiService _api;
  Box? _caja;

  /// Cambia cada vez que se abre una caja o se vacía: marca qué operaciones
  /// siguen siendo de la sesión actual.
  int _epoca = 0;

  /// `_epoca` del último `vaciar()` (cierre de sesión).
  int _vaciadaEn = 0;

  /// Caja que se está abriendo ahora mismo (para no borrarla por error).
  String? _abriendo;

  static const _claveGastos = 'gastos';
  static const _claveTotal = 'total';
  static const _claveSincronizado = 'sincronizado';

  /// Abre (o crea) la caja `gastos_<idUsuario>` del usuario que acaba de iniciar
  /// sesión. Sesión 8: el id llega de `AuthController` (que ya pidió
  /// `GET /usuarios/me`), así no se repite la petición. Devuelve `false` si
  /// mientras se abría la sesión cambió (la caja no queda en uso).
  Future<bool> abrirParaUsuario(int idUsuario) async {
    final epoca = ++_epoca;
    final nombre = 'gastos_$idUsuario';
    _abriendo = nombre;
    final Box caja;
    try {
      caja = await Hive.openBox(nombre);
    } catch (_) {
      if (epoca == _epoca) _abriendo = null;
      rethrow;
    }
    if (epoca == _epoca) {
      _caja = caja;
      _abriendo = null;
      return true;
    }
    // Llegó tarde. Si en medio se cerró la sesión de esta persona y nadie más
    // está abriendo la misma caja, se borra: el cierre de sesión la habría
    // borrado si ya hubiera estado abierta.
    final cerrada = _vaciadaEn > epoca;
    final laReabreOtraApertura = _abriendo == nombre || identical(_caja, caja);
    if (cerrada && !laReabreOtraApertura && caja.isOpen) await caja.deleteFromDisk();
    return false;
  }

  /// Borra del disco la caja de [idUsuario] aunque ningún repositorio la
  /// tenga abierta (Sesión 8, Paso 4: sesión restaurada que resultó caducada).
  /// Si el borrado falla, el error sube.
  static Future<void> borrarCajaDeUsuario(int idUsuario) =>
      Hive.deleteBoxFromDisk('gastos_$idUsuario');

  /// Primera página (`skip = 0`). Si el servidor responde, REEMPLAZA la
  /// copia anterior; si falla por red, tiempo agotado o 5xx, devuelve la
  /// copia guardada (aunque sea una lista vacía) con `desdeCache: true`.
  /// Sin copia, o ante 400/401/403/404, el error sigue su camino.
  Future<({List<Gasto> gastos, int total, bool desdeCache})> obtenerGastos({
    int limit = 20,
  }) async {
    final contexto = _contextoActual();
    try {
      final r = await _api.listarGastos(skip: 0, limit: limit);
      await _guardar(contexto, r.gastos, r.total);
      return (gastos: r.gastos, total: r.total, desdeCache: false);
    } on ApiException catch (e) {
      if (!_esFallaDeInfraestructura(e)) rethrow;
      // Un 401 o un cierre de sesión pueden haber cerrado la caja mientras
      // esta petición esperaba: entonces no hay copia que leer.
      final copia = _leer(contexto);
      if (copia == null) rethrow;
      return (gastos: copia.gastos, total: copia.total, desdeCache: true);
    }
  }

  /// Página siguiente a [mostrados] (`skip = mostrados.length`). Nunca usa
  /// el respaldo: si falla, el error sube y lo ya mostrado no cambia (devolver
  /// la copia aquí sería presentar la primera página como si fuera la
  /// siguiente). Descarta los gastos que ya estaban a la vista —si el
  /// servidor recibió gastos nuevos entre una página y otra, el
  /// desplazamiento puede repetir alguno— y amplía la copia con la página.
  Future<({List<Gasto> nuevos, int total})> obtenerSiguientePagina(
    List<Gasto> mostrados, {
    int limit = 20,
  }) async {
    final contexto = _contextoActual();
    final base = List<Gasto>.of(mostrados);
    final r = await _api.listarGastos(skip: base.length, limit: limit);
    final idsMostrados = base.map((g) => g.id).toSet();
    final nuevos = r.gastos.where((g) => idsMostrados.add(g.id)).toList();
    await _guardar(contexto, [...base, ...nuevos], r.total);
    return (nuevos: nuevos, total: r.total);
  }

  /// Fecha y hora de la última carga exitosa, lista para mostrar.
  String get ultimaSincronizacion {
    final caja = _caja;
    final iso = caja != null && caja.isOpen ? caja.get(_claveSincronizado) as String? : null;
    final fecha = iso == null ? null : DateTime.tryParse(iso)?.toLocal();
    if (fecha == null) return 'desconocida';
    String dos(int n) => n.toString().padLeft(2, '0');
    return '${dos(fecha.day)}/${dos(fecha.month)} ${dos(fecha.hour)}:${dos(fecha.minute)}';
  }

  /// Cierra y borra del disco la caja del usuario (se llama al cerrar sesión).
  /// Desde la primera línea, ninguna operación pendiente vuelve a usar esta
  /// caja; si el borrado en disco falla, el error sube (no se oculta).
  /// Devuelve `true` si había una caja abierta y se borró.
  Future<bool> vaciar() async {
    _vaciadaEn = ++_epoca;
    _abriendo = null;
    final caja = _caja;
    _caja = null;
    if (caja == null) return false;
    await caja.deleteFromDisk();
    return true;
  }

  /// Sin respuesta HTTP (sin conexión, tiempo agotado) o 5xx. Un 4xx es una
  /// respuesta válida del servidor y no se tapa con datos viejos.
  bool _esFallaDeInfraestructura(ApiException e) =>
      e.statusCode == null || e.statusCode! >= 500;

  _Contexto? _contextoActual() {
    final caja = _caja;
    return caja == null ? null : _Contexto(caja, _epoca);
  }

  /// La operación sigue siendo de la sesión actual y su caja sigue abierta.
  bool _vigente(_Contexto? c) =>
      c != null && c.epoca == _epoca && identical(c.caja, _caja) && c.caja.isOpen;

  Future<void> _guardar(_Contexto? contexto, List<Gasto> gastos, int total) async {
    if (!_vigente(contexto)) return;
    // Un solo `putAll`: lista, total y fecha se escriben juntos, así la
    // copia nunca mezcla la lista de una carga con el total de otra.
    await contexto!.caja.putAll({
      _claveGastos: gastos.map((g) => g.toMap()).toList(),
      _claveTotal: total,
      _claveSincronizado: DateTime.now().toIso8601String(),
    });
  }

  ({List<Gasto> gastos, int total})? _leer(_Contexto? contexto) {
    if (!_vigente(contexto)) return null;
    final caja = contexto!.caja;
    final guardado = caja.get(_claveGastos);
    if (guardado is! List) return null;
    final gastos = guardado.map((m) => Gasto.fromMap(m as Map)).toList();
    final total = caja.get(_claveTotal);
    return (gastos: gastos, total: total is int ? total : gastos.length);
  }
}

/// La caja y la época con que empezó una operación del repositorio.
class _Contexto {
  _Contexto(this.caja, this.epoca);
  final Box caja;
  final int epoca;
}
