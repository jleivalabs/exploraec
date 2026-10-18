import 'package:get/get.dart';

import '../models/gasto.dart';
import '../repositories/gastos_repository.dart';
import '../services/api_exception.dart';
import '../services/gastos_api_service.dart';
import 'places_controller.dart' show EstadoCarga;

/// Estado de la sección Gastos (patrón de la Sesión 4: el controller guarda
/// el estado y `Obx` reconstruye la pantalla). Reutiliza `EstadoCarga`; el
/// "vacío" se deriva de `gastos.isEmpty` con estado `exito`. Desde la
/// Sesión 7 los gastos pasan por `GastosRepository` (servidor primero,
/// caché de Hive como respaldo).
class GastosController extends GetxController {
  static const int _tamanoPagina = 20;

  final GastosApiService _api = GastosApiService();
  late final GastosRepository _repository = GastosRepository(_api);

  final RxList<Gasto> gastos = <Gasto>[].obs;
  final Rx<EstadoCarga> estado = EstadoCarga.exito.obs;
  final RxString mensajeError = ''.obs;
  final RxInt totalEnServidor = 0.obs;

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

  final RxBool sesionActiva = false.obs;
  final RxBool autenticando = false.obs;
  final RxString mensajeAuth = ''.obs;

  /// Con la copia local a la vista no se pide la página siguiente: el
  /// servidor no responde y el desplazamiento no sería coherente.
  bool get hayMas => !desdeCache.value && gastos.length < totalEnServidor.value;

  Future<void> entrar(String email, String password) async {
    autenticando.value = true;
    mensajeAuth.value = '';

    // Por qué: registro -> login -> listar dependen uno del otro; `await`
    // permite escribirlos en orden. Un 400 en el registro significa "el
    // correo ya existe": se ignora y se sigue al login.
    try {
      try {
        await _api.registrar(email, password);
      } on ApiException catch (e) {
        if (e.statusCode != 400) rethrow;
      }
      await _api.login(email, password);
      await _repository.abrirParaUsuario(); // Sesión 7: caja `gastos_<id>`
      sesionActiva.value = true;
      await cargarGastos();
    } on ApiException catch (e) {
      mensajeAuth.value = e.mensaje;
    } catch (e) {
      mensajeAuth.value = 'Error inesperado: $e';
    } finally {
      autenticando.value = false;
    }
  }

  Future<void> cargarGastos() async {
    estado.value = EstadoCarga.cargando;

    // Por qué: el bloque traduce el resultado -o la excepción- a los mismos 3
    // estados de siempre; un 401 devuelve al formulario.
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
      final r = await _repository.obtenerGastos(limit: _tamanoPagina);
      gastos.value = r.gastos;
      totalEnServidor.value = r.total;
      desdeCache.value = r.desdeCache;
      mensajeCargarMas.value = '';
      estado.value = EstadoCarga.exito;
    } on ApiException catch (e) {
      if (e.statusCode == 401) {
        sesionActiva.value = false; // volver al formulario
        mensajeAuth.value = e.mensaje; // y explicar por qué
      }
      desdeCache.value = false;
      mensajeError.value = e.mensaje;
      estado.value = EstadoCarga.error;
    } catch (e) {
      desdeCache.value = false;
      mensajeError.value = 'Error inesperado: $e';
      estado.value = EstadoCarga.error;
    }
  }

  /// Siguiente página (skip = lo ya cargado), también a través del
  /// repositorio para que la copia local crezca con cada página descargada.
  /// No cambia `estado`: si falla, lo ya mostrado se conserva tal cual y el
  /// motivo queda en `mensajeCargarMas` (la lista lo muestra junto al botón,
  /// que sirve para reintentar). Sin respaldo: devolver la copia aquí sería
  /// presentar la primera página como si fuera la siguiente.
  Future<void> cargarMas() async {
    if (!hayMas || cargandoMas.value) return;
    cargandoMas.value = true;
    mensajeCargarMas.value = '';
    try {
      final r = await _repository.obtenerSiguientePagina(gastos, limit: _tamanoPagina);
      gastos.addAll(r.nuevos);
      totalEnServidor.value = r.total;
    } on ApiException catch (e) {
      mensajeCargarMas.value = e.mensaje;
    } catch (e) {
      mensajeCargarMas.value = 'Error inesperado: $e';
    } finally {
      cargandoMas.value = false;
    }
  }

  // TODO(sesion-07): borra el método `salir` de abajo (la versión de la Sesión 6) y descomenta el bloque completo. (Paso 5 — cerrar sesión)
  // Por qué: olvidar solo el token en memoria dejaba la caja de Hive de este
  // usuario en el disco del teléfono (sin cifrar). Ahora además se cierra y
  // se borra (`vaciar`), para que otra persona que use el mismo teléfono no
  // pueda ver estos gastos. Se espera a que la caja desaparezca antes de
  // volver al formulario; la caja `favoritos` no se toca.
  Future<void> salir() async {
    _api.cerrarSesion();
    await _repository.vaciar();
    gastos.clear();
    totalEnServidor.value = 0;
    desdeCache.value = false;
    cargandoMas.value = false;
    mensajeCargarMas.value = '';
    estado.value = EstadoCarga.exito;
    sesionActiva.value = false;
  }

  /// Solo práctica (Paso 8): la siguiente petición responderá 401.
  void invalidarTokenParaPruebas() => _api.invalidarTokenParaPruebas();
}
