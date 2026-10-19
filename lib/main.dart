import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'bindings/places_binding.dart';
import 'controllers/auth_controller.dart';
// Por qué: el diccionario de textos vive en su propio archivo; sin este import, `AppTranslations` no existe aquí.
import 'i18n/app_translations.dart';
import 'screens/assistant_screen.dart';
import 'screens/favorites_screen.dart';
import 'screens/gastos_screen.dart';
import 'screens/home_screen.dart';
import 'screens/map_screen.dart';
import 'services/ai_assistant_service.dart';
import 'services/api_client.dart';
// TODO(sesion-07): OPCIONAL — descomenta la línea de abajo (Paso 6 — idioma guardado). No borres nada.
import 'services/settings_service.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  // Hive necesita el motor de Flutter listo antes de pedirle al sistema
  // operativo la carpeta donde guardar sus archivos — por eso `main` ahora
  // es `async` y arranca con `ensureInitialized()` antes que nada más.
  WidgetsFlutterBinding.ensureInitialized();
  await Hive.initFlutter();
  // Solo la caja de favoritos: la de gastos depende de QUIÉN inicie sesión,
  // así que se abre después, en `GastosRepository.abrirParaUsuario()`.
  await Hive.openBox<Map>('favoritos');
  // TODO(sesion-07): OPCIONAL — descomenta la línea de abajo (Paso 6 — idioma guardado). No borres nada.
  // Por qué: el idioma elegido se guarda en su propia caja de Hive
  // (`ajustes`). Hive solo deja leer una caja que ya está abierta, y
  // `GetMaterialApp` necesita el idioma al construirse, así que la caja
  // se abre aquí, antes de `runApp`, igual que la de arriba.
  await SettingsService.abrir();
  // Sesión 8: un solo `ApiClient` (dio) y un solo `AuthController` para toda
  // la app, registrados antes de `runApp` (las pantallas de Gastos los buscan
  // con `Get.find`). El token NO se guarda en Hive: va en el almacenamiento
  // seguro (`SecureTokenStorage`).
  Get.put(ApiClient(), permanent: true);
  Get.put(AuthController(), permanent: true);
  // Sesión 9: el cliente del proxy del asistente (no lleva ninguna clave de IA).
  Get.put(AiAssistantService(), permanent: true);
  runApp(const ExploraEcApp());
}

/// `MaterialApp` → `GetMaterialApp` — Sesión 4. Sigue siendo Material por
/// debajo (mismo `theme`, mismos widgets); `GetMaterialApp` agrega encima
/// la navegación de GetX (`Get.to`, usada desde esta sesión en `PlaceCard`
/// y `AddPlaceScreen`) y `initialBinding`, que registra `PlacesController`
/// una sola vez, antes de que cualquier pantalla lo necesite.
class ExploraEcApp extends StatelessWidget {
  const ExploraEcApp({super.key});

  @override
  Widget build(BuildContext context) {
    return GetMaterialApp(
      title: 'ExploraEC',
      theme: AppTheme.theme,
      darkTheme: AppTheme.darkTheme,
      themeMode: ThemeMode.system,
      // Por qué: `translations` le da a GetX el diccionario de textos,
      // `locale` elige el idioma con el que arranca y `fallbackLocale` el
      // que se usa si falta una clave. Con esto, `'clave'.tr` ya funciona.
      translations: AppTranslations(),
      // TODO(sesion-07): OPCIONAL — borra la línea `locale: const Locale('es', 'EC'),` de abajo y descomenta la siguiente. (Paso 6 — idioma guardado)
      // Por qué: una línea fija (`const Locale('es', 'EC')`) siempre
      // arrancaba en español. Esta lee el idioma guardado en Hive (y usa
      // español si nunca se eligió otro).
      locale: SettingsService.idioma,
      fallbackLocale: const Locale('es', 'EC'),
      initialBinding: PlacesBinding(),
      home: const RootShell(),
    );
  }
}

/// Contenedor raíz con la barra de navegación inferior — Sesión 2.
class RootShell extends StatefulWidget {
  const RootShell({super.key});

  @override
  State<RootShell> createState() => _RootShellState();
}

class _RootShellState extends State<RootShell> {
  int _indiceActual = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: switch (_indiceActual) {
        0 => const HomeScreen(),
        1 => const MapScreen(),
        2 => const FavoritesScreen(),
        3 => const GastosScreen(),
        _ => const AssistantScreen(),
      },
      bottomNavigationBar: BottomNavigationBar(
        // Con 4 pestañas Flutter cambia por defecto al tipo `shifting`
        // (etiquetas ocultas salvo la activa); `fixed` las muestra todas.
        type: BottomNavigationBarType.fixed,
        currentIndex: _indiceActual,
        onTap: (i) => setState(() => _indiceActual = i),
        // Por qué: `.tr` no es una constante (depende del idioma activo), por
        // eso el `const` desaparece de la lista y de cada ícono que sigue
        // siéndolo. Los textos fijos de abajo nunca cambiarían de idioma.
        items: [
          BottomNavigationBarItem(icon: const Icon(Icons.home), label: 'inicio'.tr),
          BottomNavigationBarItem(icon: const Icon(Icons.map), label: 'mapa'.tr),
          BottomNavigationBarItem(icon: const Icon(Icons.favorite), label: 'favoritos'.tr),
          BottomNavigationBarItem(icon: const Icon(Icons.receipt_long), label: 'gastos'.tr),
          BottomNavigationBarItem(icon: const Icon(Icons.auto_awesome), label: 'asistente'.tr),
        ],
      ),
    );
  }
}
