import 'package:geolocator/geolocator.dart';
import 'package:get/get.dart';
import 'package:hive/hive.dart';

import '../models/place.dart';
import '../services/location_service.dart';

enum EstadoCarga { cargando, exito, error }

/// Fuente única de verdad de los lugares — Sesión 4. Antes de esta sesión el
/// estado de la lista (su `Future`, las banderas de simulación y el
/// `setState`) vivía atrapado dentro de `HomeScreen`, y la pantalla se
/// enteraba de un lugar nuevo solo recargando a mano al volver del
/// formulario. Ahora vive aquí, registrado una sola vez por
/// `PlacesBinding` y obtenido con `Get.find()` (vía `GetView`, ver
/// `HomeScreen`): cualquier pantalla futura lo lee sin repetir esa carga.
///
/// Desde la Sesión 5 también guarda la posición real del usuario
/// (`posicion`, con su propio estado) para que el Mapa —y, en la Sesión 6,
/// la consulta a la Overpass API— la lean sin pedirla de nuevo al sistema
/// operativo. Desde la Sesión 7 los favoritos se guardan en una caja de Hive.
class PlacesController extends GetxController {
  final RxList<Place> lugares = <Place>[].obs;
  final Rx<EstadoCarga> estado = EstadoCarga.cargando.obs;
  final RxString mensajeError = ''.obs;
  final Rx<Position?> posicion = Rx<Position?>(null);
  final Rx<EstadoCarga> estadoPosicion = EstadoCarga.cargando.obs;
  final RxString mensajeErrorPosicion = ''.obs;

  bool _modoDebugError = false;
  bool _modoDebugVacio = false;

  /// Estado derivado (Paso 5): se calcula a partir de `lugares`, no se
  /// guarda aparte. Un `Obx` que lo lea se actualiza cuando cambia la lista.
  int get total => lugares.length;

  /// Worker que avisa cada vez que `estado` pasa a error. Se guarda la
  /// referencia para cancelar la suscripción en `onClose()`.
  late final Worker _avisoDeError;

  @override
  void onInit() {
    super.onInit();
    // Se registra una sola vez aquí, no en cargarLugares(): si se
    // registrara en cada carga, cada reintento sumaría otro aviso.
    _avisoDeError = ever<EstadoCarga>(estado, (nuevo) {
      if (nuevo == EstadoCarga.error) {
        // Fondo opaco y texto del ColorScheme activo: legible en claro y oscuro.
        final esquema = Get.theme.colorScheme;
        Get.snackbar(
          'Error',
          mensajeError.value,
          backgroundColor: esquema.error,
          colorText: esquema.onError,
        );
      }
    });
    // Sesión 7: los favoritos guardados en Hive se cargan al arrancar.
    favoritos.value = _favoritosBox.values
        .map((mapa) => Place.fromMap(Map<String, dynamic>.from(mapa)))
        .toList();
    cargarLugares();
  }

  @override
  void onClose() {
    _avisoDeError.dispose();
    super.onClose();
  }

  /// Simula uno de los 3 estados a propósito, solo para esta práctica —
  /// mismo recurso que `HomeScreen` traía desde la Sesión 3, ahora
  /// centralizado aquí para que cualquier pantalla pueda mostrarlos.
  void simular(String modo) {
    _modoDebugError = modo == 'error';
    _modoDebugVacio = modo == 'vacio';
    cargarLugares();
  }

  Future<void> cargarLugares() async {
    estado.value = EstadoCarga.cargando;

    // Por qué: las 2 líneas de abajo fuerzan éxito con una lista vacía,
    // sin llamar a nada — el bloque try/catch real es exactamente la
    // misma lógica que `HomeScreen._cargar()` tenía en la Sesión 3
    // (llamar a `fetchLugaresSimulado` y traducir su resultado a los 3
    // estados), ahora centralizada aquí para que cualquier pantalla la
    // comparta en vez de cada una tener la suya. Se usa `assignAll` (y no
    // `lugares.value = resultado`) porque copia los elementos:
    // `fetchLugaresSimulado` devuelve la lista global `lugaresEjemplo`, y
    // asignarla directo haría que `lugares` y `lugaresEjemplo` fueran la
    // misma lista, con lo que `agregarLugar` duplicaría cada lugar nuevo.
    try {
      final resultado = await fetchLugaresSimulado(
        forzarError: _modoDebugError,
        forzarVacio: _modoDebugVacio,
      );
      lugares.assignAll(resultado);
      estado.value = EstadoCarga.exito;
    } catch (e) {
      mensajeError.value = '$e';
      estado.value = EstadoCarga.error;
    }
  }

  /// Pide la posición real al sistema operativo una sola vez y la deja en
  /// [posicion]; si ya la tiene, no vuelve a pedirla salvo que se pida con
  /// [forzar] (por ejemplo, desde el botón "Reintentar" del Mapa).
  Future<void> cargarPosicion({bool forzar = false}) async {
    if (posicion.value != null && !forzar) {
      estadoPosicion.value = EstadoCarga.exito;
      return;
    }
    estadoPosicion.value = EstadoCarga.cargando;
    try {
      posicion.value = await LocationService.obtenerPosicionActual();
      estadoPosicion.value = EstadoCarga.exito;
    } on LocationException catch (e) {
      mensajeErrorPosicion.value = e.mensaje;
      estadoPosicion.value = EstadoCarga.error;
    } catch (e) {
      mensajeErrorPosicion.value = '$e';
      estadoPosicion.value = EstadoCarga.error;
    }
  }

  /// Agrega un lugar creado a mano (`AddPlaceScreen`) — en memoria
  /// únicamente: no se guarda en Hive a propósito (solo se guardan los
  /// favoritos). `lugares.add`
  /// (en vez de reconstruir toda la lista) ya notifica a cualquier `Obx`
  /// que esté escuchando (Inicio y, desde la Sesión 5, el Mapa) se
  /// actualiza solo, sin el `_cargar()` manual que la Sesión 3 hacía al
  /// volver del formulario.
  void agregarLugar(Place lugar) {
    lugaresEjemplo.add(lugar);
    lugares.add(lugar);
  }

  /// Favoritos — Sesión 4 (en memoria) y Sesión 7 (persistentes). `_favoritosBox`
  /// es el almacenamiento (sobrevive reiniciar la app; `main()` ya la abrió);
  /// `favoritos` es el espejo reactivo que la UI observa con `Obx` — el
  /// patrón «Hive guarda, Rx notifica».
  final RxList<Place> favoritos = <Place>[].obs;
  final Box<Map> _favoritosBox = Hive.box<Map>('favoritos');

  bool esFavorito(Place lugar) => favoritos.any((p) => p.id == lugar.id);

  /// Otro estado derivado: se calcula a partir de `favoritos`, no se guarda.
  int get totalFavoritos => favoritos.length;

  // Por qué (Sesión 4): agregar o quitar el lugar de la lista reactiva
  // `favoritos` basta para que cualquier `Obx` que la lea (el ícono del
  // corazón, la pestaña Favoritos) se actualice solo.
  // TODO(sesion-07): borra el método `alternarFavorito` de abajo (la versión en memoria de la Sesión 4) y descomenta el bloque completo. (Paso 3 — favoritos persistentes)
  // Por qué: solo cambiar la lista reactiva `favoritos` hacía que el corazón
  // respondiera, pero todo se perdía al cerrar la app. Ahora además se
  // agrega o elimina el lugar de _favoritosBox (Hive, lo que sobrevive
  // reiniciar la app). Se guarda el `Place` completo (`toMap()`), no solo su
  // id: así un lugar creado a mano —que no vuelve a la lista de Inicio al
  // reabrir— se puede reconstruir en Favoritos.
  void alternarFavorito(Place lugar) {
    if (esFavorito(lugar)) {
      _favoritosBox.delete(lugar.id);
      favoritos.removeWhere((p) => p.id == lugar.id);
    } else {
      _favoritosBox.put(lugar.id, lugar.toMap());
      favoritos.add(lugar);
    }
  }

  /// Distancia en metros desde la posición actual hasta [lugar], o `null`
  /// mientras todavía no se conoce la posición (antes de abrir el Mapa).
  double? distanciaA(Place lugar) {
    final pos = posicion.value;
    return pos == null ? null : distanciaAPlaceEnMetros(pos, lugar);
  }
}
