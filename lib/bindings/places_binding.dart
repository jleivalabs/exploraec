import 'package:get/get.dart';

import '../controllers/gastos_controller.dart';
import '../controllers/places_controller.dart';

/// Registra las dependencias que la app necesita desde el arranque —
/// Sesión 4. `ApiClient` y `AuthController` (Sesión 8) NO van aquí: `main()`
/// los registra antes de `runApp`, como permanentes, porque toda la app
/// depende de la sesión y `GastosController` los busca al crearse.
class PlacesBinding extends Bindings {
  @override
  void dependencies() {
    Get.put(PlacesController());
    // Sesión 6: el controller de Gastos se crea la primera vez que se usa.
    // Sesión 8: `AuthController.cerrarSesion` no lo crea si aún no existe.
    Get.lazyPut(() => GastosController());
  }
}
