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
/// - El token **no** se guarda aquí: sigue solo en memoria.
///
/// Ajuste propio respecto al starter: se conserva la paginación de la
/// Sesión 6 (páginas de `limit` elementos y el total de `X-Total-Count`).
/// La copia guarda exactamente lo que el usuario tiene a la vista —la
/// primera página y las que fue sumando con «Cargar más»— junto con el
/// total que informó el servidor, así una copia parcial se reconoce como
/// tal (por ejemplo, 40 guardados de 45).
class GastosRepository {
  GastosRepository(this._api);

  final GastosApiService _api;
  Box? _caja;

  static const _claveGastos = 'gastos';
  static const _claveTotal = 'total';
  static const _claveSincronizado = 'sincronizado';

  /// Abre (o crea) la caja del usuario que acaba de iniciar sesión. El id sale
  /// de `GET /usuarios/me`, no del correo escrito en el formulario.
  Future<void> abrirParaUsuario() async {
    final id = await _api.obtenerIdUsuario();
    _caja = await Hive.openBox('gastos_$id');
  }

  /// Primera página (`skip = 0`). Si el servidor responde, REEMPLAZA la
  /// copia anterior; si falla por red, tiempo agotado o 5xx, devuelve la
  /// copia guardada (aunque sea una lista vacía) con `desdeCache: true`.
  /// Sin copia, o ante 400/401/403/404, el error sigue su camino.
  Future<({List<Gasto> gastos, int total, bool desdeCache})> obtenerGastos({
    int limit = 20,
  }) async {
    try {
      final r = await _api.listarGastos(skip: 0, limit: limit);
      await _guardar(r.gastos, r.total);
      return (gastos: r.gastos, total: r.total, desdeCache: false);
    } on ApiException catch (e) {
      final copia = _leer();
      if (!_esFallaDeInfraestructura(e) || copia == null) rethrow;
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
    final r = await _api.listarGastos(skip: mostrados.length, limit: limit);
    final idsMostrados = mostrados.map((g) => g.id).toSet();
    final nuevos = r.gastos.where((g) => idsMostrados.add(g.id)).toList();
    await _guardar([...mostrados, ...nuevos], r.total);
    return (nuevos: nuevos, total: r.total);
  }

  /// Fecha y hora de la última carga exitosa, lista para mostrar.
  String get ultimaSincronizacion {
    final iso = _caja?.get(_claveSincronizado) as String?;
    final fecha = iso == null ? null : DateTime.tryParse(iso)?.toLocal();
    if (fecha == null) return 'desconocida';
    String dos(int n) => n.toString().padLeft(2, '0');
    return '${dos(fecha.day)}/${dos(fecha.month)} ${dos(fecha.hour)}:${dos(fecha.minute)}';
  }

  /// Cierra y borra del disco la caja del usuario (se llama al cerrar sesión).
  Future<void> vaciar() async {
    await _caja?.deleteFromDisk();
    _caja = null;
  }

  /// Sin respuesta HTTP (sin conexión, tiempo agotado) o 5xx. Un 4xx es una
  /// respuesta válida del servidor y no se tapa con datos viejos.
  bool _esFallaDeInfraestructura(ApiException e) =>
      e.statusCode == null || e.statusCode! >= 500;

  Future<void> _guardar(List<Gasto> gastos, int total) async {
    final caja = _caja;
    if (caja == null) return;
    // Un solo `putAll`: lista, total y fecha se escriben juntos, así la
    // copia nunca mezcla la lista de una carga con el total de otra.
    await caja.putAll({
      _claveGastos: gastos.map((g) => g.toMap()).toList(),
      _claveTotal: total,
      _claveSincronizado: DateTime.now().toIso8601String(),
    });
  }

  ({List<Gasto> gastos, int total})? _leer() {
    final guardado = _caja?.get(_claveGastos);
    if (guardado is! List) return null;
    final gastos = guardado.map((m) => Gasto.fromMap(m as Map)).toList();
    final total = _caja?.get(_claveTotal);
    return (gastos: gastos, total: total is int ? total : gastos.length);
  }
}
