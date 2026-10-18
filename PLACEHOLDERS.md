# Placeholders de esta rama (sesion-06)

Punto de partida: ExploraEC con lugares y mapa de las Sesiones 1-5 intactos, más la sección nueva **Gastos**, que habla con el backend de gastos del módulo anterior. Tráela con:

```bash
git fetch starter
git checkout starter/sesion-06 -- lib pubspec.yaml PLACEHOLDERS.md
flutter pub get
```

Los cambios nativos (permiso de internet y tráfico HTTP en claro) se hacen **a mano** en tu proyecto, porque `android/` no vive en este repo (ver `README.md`).

## Qué descomentar

| Archivo | Qué descomentar | Paso de la práctica |
|---|---|---|
| `lib/controllers/gastos_controller.dart` | `entrar(...)` (registro → login → listar) y `cargarGastos()` | Paso 7 |
| `lib/services/gastos_api_service.dart` | Cambiar `.timeout(const Duration(seconds: 15))` por 1 ms y devolverlo a 15 s | Paso 9 |
| `lib/screens/gastos_screen.dart` | *(Opcional)* `RefreshIndicator` (borrar el `return _buildLista(...)` y descomentar el bloque) | Paso 10 |

## Pruebas

`test/gastos_controller_test.dart` prueba el controller con un servidor falso (`MockClient`): no necesita el backend. En el starter, sus 7 pruebas fallan hasta completar el Paso 7. **En este proyecto el Paso 7 ya está hecho**: el archivo trae esas 7 más 12 propias (19 en total) y todas pasan. Ejecutarlas: `flutter test`.

## Integración en este proyecto (Paso 5)

Como en la Sesión 5, este proyecto **no** usó `git checkout starter/sesion-06 -- lib pubspec.yaml`: habría eliminado mejoras propias (Claude Design, playground, `google_fonts`, `tileProvider` del mapa, comentarios `// Por qué:`, colores y guardado de avisos, limpieza del worker, distancia junto a la categoría). Se combinó a mano:

- **Tomados tal cual del starter:** `lib/config/api_config.dart`, `lib/controllers/gastos_controller.dart`, `lib/models/gasto.dart`, `lib/screens/gastos_screen.dart`, `lib/services/api_exception.dart`, `lib/services/gastos_api_service.dart` (se trajeron con sus `TODO(sesion-06)` inactivos; los Pasos 7 y 10 los activaron después y en `lib/` ya no queda ninguno).
- **Combinados:** `PlacesBinding` (`Get.lazyPut(() => GastosController())`), `main.dart` (cuarta pestaña Gastos y `BottomNavigationBarType.fixed`), `AppTranslations` (clave `gastos`: Gastos / Expenses) y `pubspec.yaml` (`http: ^1.2.2`, conservando `google_fonts: 9.0.0` y las dependencias de la Sesión 5).
- **Pruebas (Paso 7):** `test/gastos_controller_test.dart` incorpora las 7 pruebas del starter más comprobaciones propias (orden registro → login → listado, formatos JSON/formulario, cabecera Bearer, errores que cortan el flujo, `autenticando`, total del servidor y conservación de datos ante un fallo de recarga), todas con `MockClient`, sin backend real.
- **Android (a mano):** `AndroidManifest.xml` tiene `android.permission.INTERNET` y `android:usesCleartextTraffic="true"` en `<application>`, además de los permisos de ubicación de la Sesión 5. **El tráfico HTTP sin cifrar es solo para desarrollo** (backend local en `http://10.0.2.2:8000`); una app publicada debe usar HTTPS y quitar ese atributo o limitarlo con `network_security_config`.

### Estado esperado tras el Paso 7

La pestaña Gastos muestra el formulario; **Entrar** ejecuta registro (un 400 por correo existente se ignora) → login → listado contra el backend y pasa a la lista con los estados cargando/vacío/error. Un 401 al listar vuelve al formulario con el motivo; un fallo de recarga conserva en el controller los gastos ya cargados. El timeout definitivo es de 15 s: el Paso 9 se probó a mano con 1 ms (mensaje de tiempo agotado) y se restauró; después de restaurarlo fue necesario volver a iniciar sesión desde el formulario. Lugares, mapa, favoritos e idioma siguen como en la Sesión 5.

### Paso 10 (opcional) — deslizar para actualizar: activado

En `GastosScreen` la lista va dentro de un `RefreshIndicator` con `onRefresh: controller.cargarGastos` (bloque del curso). El `ListView` ya usaba `AlwaysScrollableScrollPhysics`, así que el gesto funciona aunque la lista tenga pocos gastos y no llene la pantalla. Mientras recarga se ve el `LoadingView` (el estado pasa a `cargando`), y en los estados vacío y error no hay lista que deslizar: se usa el botón de recargar o "Reintentar". El botón de recargar de la barra y "Cargar más" siguen igual. El mini-reto del aviso al terminar no está implementado.

Prueba: `widget_test.dart` desliza la lista con un solo gasto y comprueba que se vuelve a pedir `GET /gastos/?skip=0&limit=20` y que aparece el gasto nuevo, con un backend simulado y sin conexiones reales.

### Ajustes propios heredados de la Sesión 5 (se conservan)

- `MapScreen` acepta un `tileProvider` opcional; `null` (lo que usa la app) mantiene el proveedor de red de OpenStreetMap. Las pruebas pasan uno local para no descargar teselas.
- La distancia de `PlaceCard` va en la misma línea que la categoría, para no desbordar las celdas estrechas de la grilla (`childAspectRatio: 2.2`).

## Estado final de la Sesión 6

- **Comprobado a mano en el emulador** contra el backend local (`proyecto-curso-spec-kit` con Docker): registro e inicio de sesión, lista vacía y con tres gastos, desconexión del backend y recuperación, sesión inválida con regreso al formulario, validación de contraseña corta, paginación con `X-Total-Count`, timeout (Paso 9) y deslizar para actualizar (Paso 10).
- **Comprobado en PostgreSQL** (consultas de solo lectura): los tres gastos del usuario de práctica y que el usuario rechazado por contraseña corta no existe.
- **Pruebas automáticas:** `flutter analyze` sin incidencias y 88 pruebas aprobadas (`widget_test.dart` y `gastos_controller_test.dart`), sin backend real ni descarga de teselas.
- **Pendiente para otras sesiones:** el token vive solo en memoria (se pierde al reiniciar la app; almacenamiento seguro en la Sesión 8) y el tráfico HTTP sin cifrar es solo para desarrollo.

