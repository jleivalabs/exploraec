# Placeholders de esta rama (sesion-10, en curso)

## Sesión 10 — Punto de partida y Paso 1

- **Integrado (sin `git checkout` de carpetas completas):** del starter, `lib/utils/reporte_errores.dart` (bloque del Paso 2 comentado), `lib/widgets/error_pantalla_view.dart`, `lib/screens/pantalla_con_fallo.dart`, `test/sesion_10_test.dart` (Paso 3 comentado), `docs/`, `AGENTS.md` y `CLAUDE.md`. Combinados a mano: `main.dart` (`ReporteErrores.instalar()` antes de `runApp`, `localizationsDelegates` y `supportedLocales` es_EC/en_US), `pubspec.yaml` (`flutter_localizations`, del SDK), `analysis_options.yaml` (excluye `lib/playground/**`) y `gastos_screen.dart` (opciones de depuración «Error de pantalla» y «Error asíncrono»; «Acerca de» del Paso 10 comentado).
- **Conservado:** nuestra pantalla del Asistente con la marca de sesión; opcionales anteriores inactivos (cambio de contraseña de la Sesión 8, chips de la Sesión 9). El proxy no se cambió.
- **Pendiente para sus pasos:** `.claude/settings.json` (permisos, Paso 6), las tres líneas de `.gitignore` (Paso 4) y los workflows de `.github/` (Pasos 5 y 8). Pasos 2, 3 y 10 sin activar.
- **Ajuste de prueba:** con `flutter_localizations`, el botón «atrás» de Material tiene el tooltip en español y `tester.pageBack()` (que busca «Back») ya no lo encontraba; «Tocar una tarjeta abre el detalle…» ahora toca `BackButton` por su tipo, con la misma comprobación.
- **Resultados reales:** `flutter analyze` sin incidencias. La suite completa (una ejecución, 20 s) dio **207 aprobadas y 2 fallidas**: la esperada del Paso 2 («instalar() reemplaza la pantalla roja…») y la de `pageBack()` descrita arriba. Tras el ajuste, esa prueba pasa ejecutada sola; la suite completa no se repitió (previsto: 208 aprobadas y 1 fallida, la del Paso 2). Sin procesos ni carpetas temporales pendientes.

## Sesión 10 — Paso 2 (errores no controlados)

- Activado el bloque `TODO(sesion-10) Paso 2` de `ReporteErrores.instalar()`, tal como viene del starter: `FlutterError.onError` (presenta y registra), `PlatformDispatcher.instance.onError` (registra, avisa y absorbe) y `ErrorWidget.builder` (vista amistosa `ErrorPantallaView` en lugar de la pantalla roja). `registrar` guarda el mensaje ya limpio (sin cabeceras `Bearer` ni tokens JWT). Se quitó el `ignore_for_file: unused_import` que solo hacía falta con el bloque comentado. No cambia el tratamiento de errores de red, de negocio ni de sesión. Pasos 3 y 10 sin activar.
- **Resultados automáticos:** `flutter analyze` sin incidencias y la suite completa (una ejecución, 19 s) con **209 pruebas aprobadas**, incluida la prueba de navegación ajustada («Tocar una tarjeta abre el detalle…»). Sin procesos ni carpetas temporales pendientes.
- **Comprobado a mano:** en el emulador, menú ⋮ de Gastos → «Error de pantalla (solo práctica)» muestra la vista amistosa, y «Error asíncrono (solo práctica)» muestra el aviso con la pantalla de Gastos aún visible.
- **Pendiente (manual):** revisar el registro de la consola (`[ExploraEC] error no controlado -> …`) para confirmar que no aparecen tokens.

## Sesión 10 — Paso 3 (pruebas de widgets)

- Descomentadas las tres pruebas del bloque `TODO(sesion-10) Paso 3` de `test/sesion_10_test.dart`, sin cambios en sus comprobaciones: sin sesión se ve el motivo y el botón «Iniciar sesión»; registrar con contraseña corta se rechaza sin llamar al servidor; una pantalla que falla muestra la vista amistosa y no la roja. Se quitó el `ignore_for_file` que solo hacía falta con las pruebas comentadas. No usan Hive.
- **Resultado ejecutado:** `flutter analyze` sin incidencias y `test/sesion_10_test.dart` completo (una ejecución, 5 s) con **6 pruebas aprobadas**. La suite global no se repitió: el total previsto es **212** (209 anteriores + 3), sin verificar en una ejecución completa.
- **Comprobado a mano (Paso 3):** sin conexión se conservaron los cuatro gastos (copia local); al recuperar la conexión la lista volvió sin banner y el backend registró `GET /gastos/` con 200.

## Sesión 10 — Paso 4 (secretos y registros)

- **Búsqueda de secretos** en `lib/`, `test/`, `mock-server/`, `docs/`, `android/app/src`, `pubspec.yaml`, `analysis_options.yaml`, `AGENTS.md`, `CLAUDE.md` y `.gitignore` (claves `AIza…` y `sk-…`, JWT, claves privadas y asignaciones del tipo `password/secret/api_key = "…"`): **ningún secreto real**. Único hallazgo: un JWT **ficticio** en `test/sesion_10_test.dart:61` (prueba de `limpiar()`, firma de relleno). Las contraseñas y tokens de las pruebas son sintéticos (`clave-1234`, `token-sintetico-…`). `GEMINI_API_KEY`, `E2E_CLAVE` y `SECRET_KEY` aparecen solo como **nombres** de variables en código y documentación.
- **Registros:** la app solo escribe en consola desde `ReporteErrores.registrar` (`debugPrint` del mensaje ya pasado por `limpiar()`); no hay `print` fuera de `lib/playground/` ni `LogInterceptor` de `dio`. El proxy registra tamaño y nombres de campos, nunca contenido, cabeceras ni clave; `probar-e2e.js` no imprime el token ni la contraseña. `limpiar()` reemplaza cabeceras `Bearer …` y textos con forma de JWT (`eyJ….….…`), y sus pruebas lo comprueban; **no** cubre cualquier secreto posible (por ejemplo, una contraseña o una clave sin ese formato dentro del mensaje de un error). Riesgo residual: los mensajes de error del MCP (`e.message`) se registran sin filtrar.
- **`.gitignore`:** añadidas `.env`, `.claude/settings.local.json` y `CLAUDE.local.md` (comprobadas con `git check-ignore`). Ninguno de los tres está versionado ni existe en la carpeta; el historial (`git log --all`) no contiene ningún `.env`. No hizo falta reescribir el historial.
- **Pendiente (manual, Paso 2):** la captura del registro de la consola sigue pendiente; esta revisión del código no la sustituye.
- Sin cambios en producción, permisos ni workflows; no se ejecutaron análisis ni pruebas (solo cambiaron documentación y `.gitignore`).


## Sesión 10 — Paso 5 (CI en GitHub Actions)

- **`.github/workflows/ci.yml`** (del starter) con `flutter-version: '3.47.5'` fijada (la misma con la que validamos; Dart 3.13.4 cumple `sdk: ">=3.5.0 <4.0.0"`). Se dispara en `push` a cualquier rama (`cierre-s10`, `prueba-roja`…), en `pull_request` y a mano (`workflow_dispatch`); permisos `contents: read`; `concurrency` cancela la ejecución anterior de la misma rama. Ejecuta `flutter pub get`, `flutter analyze --no-fatal-infos` y `flutter test`: no necesita backend, emulador, Gemini ni secretos. Versiones de las acciones comprobadas en sus repositorios oficiales: `actions/checkout@v7`, `actions/setup-java@v6`, `subosito/flutter-action@v2`. YAML validado localmente.
- **Registro del error MCP sin filtrar, corregido:** `mock-server/mcp-cliente.js` ya no escribe `e.message` (podía traer texto del backend); registra «MCP no disponible (código N): se usa el resumen que envió la app», con el código solo si es un estado HTTP válido (`codigoSeguro`). `probar-e2e.js` aplica el mismo criterio en su paso 3/4 y conserva su resultado. El respaldo con el resumen de la app no cambia.
- **Verificación local (ficticia):** con un MCP falso que responde 500 o un error de herramienta con un marcador ficticio, el proxy (modo REGLAS, sin `GEMINI_API_KEY`) respondió 200 con `X-Resumen-Origen: app`, y ni el marcador ni el token ficticio aparecieron en su consola ni en la de `probar-e2e.js`, que siguió marcando ❌ en el paso 3/4 (salida 1). `node --check` correcto en los JS modificados.
- **Resultados:** `flutter analyze` sin incidencias y suite completa (una ejecución, 23 s) con **212 pruebas aprobadas**. Sin procesos ni carpetas temporales pendientes.
- **CI en GitHub (comprobado):** `cierre-s10` terminó en verde con 212 pruebas; la rama `prueba-roja`, con un fallo deliberado, terminó en rojo con 211 aprobadas y 1 fallida, como se esperaba. La rama `prueba-roja` se eliminó después en local y en el remoto. Pendiente: la ejecución del pull request.
- **Anotado para el Paso 8:** `release-apk.yml` deberá compilar con `--dart-define=LLM_BACKEND_URL=http://10.0.2.2:3001` para el Asistente.

## Sesión 10 — Paso 6 (arnés del agente)

- **`AGENTS.md` — Reglas del estudiante:** (1) conservar las protecciones de sesión, paginación y caché, y justificar y probar cualquier cambio que las afecte; (2) reutilizar los componentes existentes y mantener los textos nuevos de interfaz en español e inglés con las traducciones del proyecto. Son **instrucciones** para el agente: no las hace cumplir el sistema de permisos.
- **`.claude/settings.json`** (del starter, ajustado):
  - `allow`: `flutter analyze`, `flutter test`, `dart format`, `git status` y `git diff` (con o sin argumentos), en `Bash(...)` y su equivalente `PowerShell(...)`; no se permitió ningún comando más.
  - `ask`: `git commit` (Bash y PowerShell).
  - `deny`: `Read(**/.env)` y `Read(**/.env.*)` (también en subcarpetas), y `git push` y `git tag` (Bash y PowerShell).
- **Validación:** JSON correcto y las 18 reglas coinciden con el patrón oficial `permissionRule` del esquema de ajustes de Claude Code (SchemaStore), que incluye `PowerShell` como herramienta. **Comprobado a mano:** `/permissions` muestra las reglas Allow, Ask y Deny cargadas, y el agente citó correctamente las reglas propias de `AGENTS.md`. **No probado:** ninguna operación de publicación (push, etiquetas) para verificar los bloqueos.
- **Límites (según la documentación oficial, no probados aquí):** las reglas comparan el **texto** del comando, no son una frontera de seguridad: por ejemplo, `git push *` no detiene `git -C . push`. `Read` bloquea `.env` en las herramientas de archivos, Grep, Glob y comandos como `cat`, pero no un `grep -r` que no lo nombre ni un script que lo abra por su cuenta (para eso, el sandbox). `deny` rige en todos los modos y ningún otro nivel puede volver a permitirlo; el efecto de `ask` depende del modo de permisos, así que no se garantiza que pida confirmación en cualquier modo. Cómo se analizan los comandos de PowerShell está poco documentado.
- Sin cambios en configuraciones personales o globales ni hooks; sin pruebas Flutter.

## Sesión 10 — Paso 7 (filtro de gastos por categoría)

- **Funcionalidad:** fila de `ChoiceChip` encima de la lista de Gastos con «Todas» y una opción por cada categoría de los gastos cargados (sin repetir, en orden de aparición). Elegir una muestra solo sus gastos; «Todas» restablece la lista cargada.
- **Implementación (solo controller, pantalla y traducciones):**
  - `GastosController`: `categoriaFiltro` (`null` = «Todas»), `filtrar(...)`, `categoriasCargadas` y `gastosVisibles`, calculados a partir de `gastos`. El filtro es local: no cambia `gastos`, la caché, `hayMas`, la paginación ni la API, y no descarga más páginas.
  - `GastosScreen`: chips (debajo del banner de copia local), lista filtrada dentro del mismo `RefreshIndicator`, y el aviso «No hay gastos de X entre los cargados» cuando la categoría elegida no tiene coincidencias. «Cargar más» sigue visible mientras `hayMas`, aunque no haya coincidencias o no haya gastos cargados; «Aún no registras gastos en este viaje» solo aparece si no hay gastos ni páginas pendientes.
  - `app_translations.dart`: `filtro_todas` (Todas / All) y `filtro_sin_coincidencias` (español / inglés). Los nombres de categoría vienen del backend y se muestran tal cual.
- **Selección:** se conserva al recargar (también sobre la copia sin conexión) y al borrar el último gasto de la categoría (su chip queda visible y seleccionado); se restablece a «Todas» al cambiar de sesión (`_vaciarEstado`).
- **Pruebas nuevas — `test/filtro_gastos_test.dart` (10):** chips sin repetir; elegir «comida» sin tocar la lista ni la caché ni pedir nada al servidor; volver a «Todas»; «Cargar más» con filtro (`skip=20&limit=20`) suma las coincidencias nuevas; sin coincidencias y con páginas pendientes se avisa y «Cargar más» trae las nuevas; recargar conserva la selección (con y sin conexión); al cambiar de sesión B no hereda el filtro de A; «Aún no registras gastos» solo sin gastos ni páginas; con páginas pendientes una página vacía no se presenta como «sin gastos»; textos en inglés. Usan el servidor falso de `dio` y una caja de gastos en memoria (sin E/S real de Hive en el reloj simulado).
- **Corrección del montaje de las pruebas:** `dio` ejecuta cada interceptor dentro de `Future(() …)` (temporizador de duración cero), que en el reloj simulado de `testWidgets` solo se dispara al avanzar el reloj. Por eso iniciar y cerrar sesión, la carga inicial y `eliminar` se esperan dentro de `tester.runAsync`; los toques seguidos de `pumpAndSettle` no lo necesitan. No se aumentaron tiempos de espera ni se quitaron comprobaciones.
- **Ejecución interrumpida (antes de la corrección):** la primera suite completa se cortó por el límite de 300 s: la primera prueba del archivo nuevo quedó esperando en `iniciarSesion` y las 10 no terminaron (212 aprobadas, el resto de archivos correctos).
- **Validación final (después de la corrección):** `test/filtro_gastos_test.dart` completo con **10 aprobadas** (6 s); `flutter analyze` sin incidencias y la suite completa (una ejecución, 24 s, límite de 120 s) con **222 pruebas aprobadas**. Sin procesos ni carpetas temporales pendientes.
- **Caso límite corregido (tras la revisión del diff):** los chips se ocultaban si la lista cargada quedaba vacía, aunque hubiera una categoría elegida y páginas pendientes: el filtro seguía activo sin verse. Ahora la fila de chips aparece si hay gastos, una categoría elegida **o** páginas pendientes (`hayMas`); el `EmptyView` sin chips se mantiene cuando no hay gastos, selección ni más páginas. Sin cambios en la API, la caché ni el cálculo de la paginación. Prueba de regresión nueva: con la lista cargada vacía, «otros» elegido y `hayMas`, siguen visibles el chip elegido, «Todas» y «Cargar más»; «Todas» quita el filtro y la carga siguiente muestra sus gastos sin el filtro anterior.
- **Validación tras la corrección:** `test/filtro_gastos_test.dart` con **11 aprobadas** (6 s); `flutter analyze` sin incidencias y la suite completa (una ejecución, 24 s, límite de 120 s) con **223 pruebas aprobadas**. Sin procesos ni carpetas temporales pendientes.
- **Comprobado a mano (emulador):** «Todas» muestra los cuatro gastos; «comida» muestra los dos almuerzos de 6.50; en inglés el chip dice «All» y, al volver a español, «Todas».
- **Pendiente (manual):** comprobar en el emulador que la selección se conserva al recargar (cubierto solo por las pruebas automáticas).

## Sesión 10 — Paso 8 (entrega continua: Release APK)

- **`.github/workflows/release-apk.yml`** (del starter, ajustado): se dispara al subir una etiqueta `v*` (crea el Release y le adjunta el APK) o a mano (`workflow_dispatch`, solo deja el APK como artefacto). Permisos `contents: write` (necesario para el Release). Flutter fijado en `3.47.5`, como CI. **Puerta de calidad:** `flutter pub get`, `flutter analyze --no-fatal-infos` y `flutter test` (toda la suite) van antes de compilar y publicar; si alguno falla, no se compila ni se publica. El APK (`build/app/outputs/flutter-apk/app-release.apk`) se guarda como artefacto y, solo con etiqueta, se adjunta al Release con notas generadas. Versiones de `actions/upload-artifact@v7` y `softprops/action-gh-release@v3` comprobadas en sus repositorios oficiales.
- **Direcciones de la app:** `API_BASE_URL` y `LLM_BACKEND_URL` (los nombres que lee el código, en `api_config.dart` y `ai_assistant_service.dart`) se toman de las variables de GitHub con el mismo nombre o, si no existen, de los valores del emulador: `http://10.0.2.2:8000` y `http://10.0.2.2:3001`. Llegan al comando como variables de entorno y se usan entre comillas, sin insertarse como código del shell.
- **Clave de IA:** esta configuración **no** incorpora ninguna clave al APK: el workflow no usa secretos ni pasa `GEMINI_API_KEY`, y la clave de Gemini permanece en el entorno del proxy. En el APK compilado localmente no aparecen `GEMINI_API_KEY` ni cadenas con forma de clave de Google (búsqueda en `libapp.so`).
- **Android (release):** el manifiesto principal ya tenía `android.permission.INTERNET`; se conservan `usesCleartextTraffic="true"` (HTTP hacia `10.0.2.2`, solo para la práctica) y las restricciones de copia (`allowBackup="false"` y `dataExtractionRules`), comprobadas en el manifiesto fusionado de release.
- **Firma de práctica:** `release` se firma con la **clave de debug** (plantilla de Flutter). Cada máquina de CI genera la suya, así que un APK de otra compilación puede no instalarse encima del anterior (firma distinta: hay que desinstalar antes). **No es una distribución de producción:** para eso harían falta una clave de firma propia en Secrets, HTTPS sin tráfico en claro y la dirección real del backend.
- **Versión:** `pubspec.yaml` en `1.0.0+1`; no había etiquetas locales ni remotas, así que corresponde `v1.0.0`.
- **Resultado local:** YAML validado; `flutter build apk --release` con ambos `--dart-define` correcto (una compilación, 83 s, `app-release.apk` de 53.2 MB; 3 avisos de las herramientas de compilación, no de la app). En el APK aparecen `10.0.2.2:8000` y `10.0.2.2:3001` y no `10.0.2.2:3000`. No se repitió la suite local (solo cambiaron el workflow y la documentación); el workflow la ejecuta completa. No se instaló el APK.
- **Permisos del agente (evidencia):** al revisar las etiquetas, `git tag -l` fue **denegado** por la regla `deny` `Bash(git tag *)` del Paso 6: bloquea también listar etiquetas, no solo crearlas. Se listaron con `git for-each-ref` (solo lectura).
- **Pendiente:** en GitHub, CI del PR actualizado; tras el merge, crear y subir `v1.0.0` (lo hace la persona) y comprobar que el workflow publica el Release con `app-release.apk`. En el emulador, instalar ese APK (desinstalando antes si la firma no coincide) y probar backend y Asistente.

## Sesión 9 — Asistente ExploraIA

Pestaña «Asistente» conectada a un proxy propio (`mock-server/`) que llama a Gemini. La app no lleva ninguna clave de IA, envía solo la pregunta y el resumen por categoría, y pide confirmación antes de registrar un gasto. **Este proyecto no usó** `git checkout starter/sesion-09 -- lib test pubspec.yaml PLACEHOLDERS.md mock-server`: se trajeron solo los archivos nuevos y el resto se combinó a mano, conservando la Sesión 8 (con su Paso 9 inactivo).

### Estado de los pasos

| Paso | Contenido | Estado |
|---|---|---|
| Punto de partida y 2 | `resumen_gastos.dart`, `ai_assistant_service.dart`, `assistant_screen.dart`, `mock-server/`, `sesion_09_test.dart`; quinta pestaña, traducción `asistente`, `obtenerResumen()` en servicio y controller (sin caché), parámetro `titulo` de `SinSesionView` | Hecho |
| 3 | Contrato del proxy (`consulta` + `resumen`; responde `respuesta` y `accion`) | Hecho |
| 4 | Preguntar: resumen del backend → proxy → respuesta | Hecho, con marca de sesión |
| 5 | Confirmación humana antes de registrar | Hecho, con marca de sesión |
| 6 | Errores: límite de 500 y proxy apagado | Hecho |
| 7 | Datos mínimos: qué viaja al proxy | Hecho |
| 8 | El proxy pide el resumen por MCP (`resumen_gastos`) y prueba de extremo a extremo | Hecho |
| 9 (opcional) | Preguntas sugeridas (chips) | **No activado** |

### Entorno de la práctica

- **Proxy en el puerto 3001** (el 3000 estaba ocupado): se enciende con la variable `PORT`; la app se ejecuta con `--dart-define=LLM_BACKEND_URL=http://10.0.2.2:3001` (la dirección no está fija en el código). Para la prueba de extremo a extremo, `PROXY_URL=http://localhost:3001`; el backend sigue en `http://localhost:8000`.
- **Gemini:** modelo `gemini-3.5-flash-lite`, con la clave solo en la variable de entorno `GEMINI_API_KEY` de la terminal del proxy; no está escrita en ningún archivo del proyecto. Sin clave, el proxy funciona en modo REGLAS con el mismo contrato.

### Decisiones de integración

- **Marca de sesión (`AuthController.marcaSesion`):** cambia cada vez que se abre o se cierra una sesión. El Asistente la guarda al preguntar y la comprueba después de cada espera (resumen, proxy, decisión del diálogo) y justo antes de `crear`; si cambió, descarta la respuesta, el error o la acción, aunque la misma persona haya vuelto a entrar. Al cambiar de sesión se limpia la pantalla y se cierra solo el diálogo de confirmación si sigue abierto. Mientras hay una consulta en curso no se envía otra.
- **Crear desde el Asistente** reutiliza `GastosController.crear`: recarga la primera página y la caché; si la recarga falla, el gasto aceptado no se repite.
- **Contraseña de `probar-e2e.js`:** además de como argumento, puede llegar en la variable temporal `E2E_CLAVE` (así no queda en el historial ni en la línea del proceso); nunca se imprime.
- **Pruebas:** `sesion_09_test.dart` borra su carpeta temporal de Hive al terminar y usa una caja de gastos en memoria (`_RepositorioEnMemoria`, el patrón de `widget_test.dart`). Antes, una escritura real a disco iniciada dentro de `testWidgets` dejaba esperando a `Hive.close()` en `tearDownAll`.

### Pruebas automáticas

`flutter analyze` sin incidencias, `node --check` correcto en `mock-server.js`, `mcp-cliente.js` y `probar-e2e.js`, y `flutter test` con **206 pruebas aprobadas** (las 194 de la Sesión 8 más 12 de `sesion_09_test.dart`: servicio y modelo, Paso 4 con consultas duplicadas, respuestas y errores de una sesión anterior y 401 del proxy, y Paso 5 con confirmar, cancelar y cambio de sesión con el diálogo abierto). Sin backend real ni Gemini: servidores falsos.

### Comprobado a mano

- **Asistente:** consulta con respuesta correcta según los datos reales; confirmación y creación de un gasto propuesto; rechazo del backend al registrar 600 (límite de 500 por categoría); error claro con el proxy apagado y recuperación al volver a encenderlo.
- **Datos mínimos (Paso 7):** al pasar de 4 a 7 gastos, la petición al proxy pasó de 379 a 382 bytes, siempre con cuatro categorías en el resumen.
- **Extremo a extremo (Paso 8):** `probar-e2e.js` real con las cuatro comprobaciones correctas; resumen con total 20.25 y comida 13. Desde la app, el proxy registró «Resumen obtenido del backend por MCP (resumen_gastos)».

### Límites conocidos

- El proxy es una **demostración** local: en un proyecto real estaría en un servidor de la organización, con límites de uso.
- **Respaldo previsto:** si el MCP falla (backend apagado o token caducado), el proxy usa el resumen que envió la app y lo indica en consola («MCP no disponible…»).
- **401 del proxy:** se muestra como error del Asistente y **no** cierra la sesión global (su `Dio` no pasa por nuestros interceptores); distinguir su origen queda pendiente.
- El resumen no tiene caché: sin conexión, el Asistente solo muestra el error.

## Sesión 8

Sesión 8: el cliente `http` se reemplaza por `dio` con interceptores, el token va al almacenamiento seguro (`flutter_secure_storage`), la sesión la maneja `AuthController` y se completa el CRUD de gastos. **Este proyecto no usó** `git checkout starter/sesion-08 -- lib test pubspec.yaml PLACEHOLDERS.md` (habría borrado la paginación, la caché acumulada, el aviso de copia parcial y las pruebas propias): se trajeron solo los archivos nuevos y el resto se combinó a mano.

## Estado de los pasos

| Paso | Bloques | Estado |
|---|---|---|
| 1 | Punto de partida (archivos nuevos, `dio` y `flutter_secure_storage` en `pubspec.yaml`, `http` ya no es dependencia directa) | Hecho |
| 2 | Interceptor del token, `iniciarSesion`, `SinSesionView` | Hecho |
| 3 | `registrar` y validadores de `register_screen.dart` | Hecho |
| 4 | `restaurarSesion` | Hecho, con ajustes (ver abajo) |
| 5 | `cargarCategorias`, `crear`, botón «+» | Hecho, con ajustes |
| 6 | `actualizar`, `eliminar`, tocar para editar, botón eliminar | Hecho, con ajustes |
| 7 | Interceptor del 401 | Hecho, con ajustes |
| 8 | Limpiar los gastos en `cerrarSesion` | **Adelantado al Paso 2**, para no perder el borrado de la caché de la Sesión 7; comprobado después con `adb` |
| 9 (opcional) | `cambiarPassword` y opción del menú | **No implementado** (bloques comentados) |

## Decisiones de integración (diferencias con el starter)

- **Paginación y caché de la Sesión 7 conservadas:** páginas de 20, total de `X-Total-Count`, copia acumulada con «Cargar más», aviso de copia parcial y de copia vacía, `RefreshIndicator`. Tras crear, editar o eliminar se recarga la primera página y se reemplaza la copia.
- **Vigencia de sesión:** `GastosController` lleva un número de sesión y `GastosRepository` recuerda la caja y la época de cada operación (también al abrir la caja y al paginar). Una respuesta tardía de otra sesión no toca lista, errores, indicadores ni caché, ni escribe en otra caja.
- **Cerrar sesión:** limpia primero la memoria (token y usuario); luego intenta borrar la caché y el token por separado; si algo falla, la sesión queda cerrada y `avisoSesion` dice qué no se borró. No crea `GastosController` desde el `lazyPut` (`isPrepared`) y un segundo cierre simultáneo reutiliza el primero.
- **Login «todo o nada»:** `usuario` se asigna al final; si `/usuarios/me` o el guardado seguro fallan, el token no queda en memoria ni guardado. `registrar` reutiliza este `iniciarSesion`.
- **Restaurar sesión (Paso 4):** token válido → usuario y gastos; 401 → cierre y aviso «caducó»; sin red → el token sigue guardado pero no en memoria, se avisa y la sesión no se abre; una restauración tardía (tras cerrar o iniciar otra sesión) no abre nada.
- **Último id de usuario en `ajustes` (`ultimo_usuario_id`):** solo como metadato de limpieza; nunca autentica ni muestra datos. Al cerrar sesión se borra únicamente `gastos_<id>` si el controller no borró ya esa caja; el id se olvida solo si el borrado funcionó (si falla, se conserva para reintentar). **Limitación:** no resuelve retroactivamente cajas antiguas creadas antes de guardar el id (o cuyo id se sobrescribió con el login de otra persona sin cerrar la sesión anterior).
- **`/usuarios/me` una sola vez:** el repositorio recibe el id de `AuthController` (`abrirParaUsuario(id)`).
- **Categorías (Paso 5):** se piden antes de la lista si faltan; su fallo no bloquea la lista ni la copia y se reintentan en la siguiente recarga.
- **Cambios aceptados pero recarga fallida (Pasos 5-6):** el error va a la lista, no al formulario (reintentar duplicaría el gasto). Un 404 al editar/eliminar recarga la lista y muestra el mensaje del servidor. El formulario conserva sus valores ante errores de negocio (límite de 500).
- **Interceptor 401 (Paso 7):** solo cuenta el 401 de una petición con el token actual (ignora el login y los 401 tardíos de otra sesión); varios 401 simultáneos comparten un cierre, aviso y navegación (`sesionCaducada`).
- **«Invalidar token»** solo aparece en modo debug (`kDebugMode`). `ErrorView` reintenta con `iniciar`.
- **Tiempos de `dio`:** 15 s **por fase** (conectar, enviar, recibir), no un límite total como el `.timeout(15 s)` del cliente `http` anterior.
- **Android:** `flutter_secure_storage` 11.2.0 declara `minSdk = 24` en su módulo Android (su README pide API 23); la app usa `flutter.minSdkVersion` = 24. Compilación `flutter build apk --debug` correcta. La copia de seguridad está desactivada (ver abajo).

## Pruebas automáticas

`flutter analyze` sin incidencias y `flutter test` con **194 pruebas aprobadas** (ninguna falla), sin backend real: `dio` usa el servidor falso `test/helpers/servidor_gastos_falso.dart` (`HttpClientAdapter`) y Hive carpetas temporales que se borran al terminar.

- `gastos_controller_test.dart`: las pruebas de las Sesiones 6-7 pasadas a `dio`/`AuthController` (sin borrar ninguna; las del flujo registro→login cambiaron de significado con pantallas separadas) más las de la Sesión 8: vigencia y respuestas tardías (lista, caché, apertura de caja, paginación), usuario A → B, fallos de borrado (token, caché, id conservado), restauración, categorías, crear/editar/eliminar, interceptor 401 y `ApiException.desde`.
- `widget_test.dart`: `SinSesionView` → `LoginScreen`, contraseña incorrecta, cerrar sesión desde el menú, formulario con error de negocio, editar y eliminar con confirmación, 404 al eliminar. La caja `gastos_<id>` va en memoria (`_RepositorioEnMemoria`); el borrado real en disco lo cubren las pruebas con `tester.runAsync` y las del controller.
- `sesion_08_test.dart`: las 15 del starter, con su carpeta temporal borrada al final y una espera explícita del cierre por caducidad (aquí la memoria se limpia antes que el disco).

## Comprobado a mano en el emulador

Contra el backend local: restauración de la sesión al reabrir la app, desconexión y recuperación, registro (contraseña corta, correo repetido, cuenta nueva), crear/editar/eliminar con confirmación, límite de 500 por categoría y sesión caducada (401). Tras caducar la sesión, `adb shell run-as com.example.exploraec ls app_flutter` muestra `favoritos.hive` y `ajustes.hive`, sin `gastos_3.hive`.

## Copia de seguridad de Android: desactivada

El README de `flutter_secure_storage` 11.2.0 advierte que la copia automática puede restaurar los datos cifrados sin su clave del Keystore (`InvalidKeyException: Failed to unwrap key`); además, la caché de gastos de Hive es personal y no está cifrada. Para esta práctica se desactivan las copias de los datos de la app:

- `android/app/src/main/AndroidManifest.xml`: `android:allowBackup="false"` (copia automática hasta Android 11) y `android:dataExtractionRules="@xml/data_extraction_rules"` en `<application>`.
- `android/app/src/main/res/xml/data_extraction_rules.xml` (nuevo): en Android 12+ `allowBackup` no cubre la transferencia entre dispositivos; las reglas excluyen todos los dominios (`root`, `file`, `database`, `sharedpref`, `external` y sus `device_*`) tanto de `<cloud-backup>` como de `<device-transfer>`.
- **Consecuencia:** favoritos e idioma siguen guardándose en el teléfono (Hive), pero **no** se restauran mediante copias de Android ni al pasar a otro dispositivo.
- **Comprobado:** `flutter build apk --debug` correcto; el manifiesto fusionado contiene ambos atributos y `data_extraction_rules.xml` está entre los recursos empaquetados. **No probado:** ninguna copia ni transferencia real entre dispositivos.

## Historial — Sesión 7

Notas de la Sesión 7 tal como quedaron (los estados de pasos y pruebas que describen son los de esa sesión).

Punto de partida del starter: ExploraEC con la sección **Gastos** de la Sesión 6 funcionando (registro → login → lista contra el backend de gastos, con el token solo en memoria) y favoritos que viven solo mientras la app está abierta. En el starter se trae con:

```bash
git fetch starter
git checkout starter/sesion-07 -- lib test pubspec.yaml PLACEHOLDERS.md
flutter pub get
```

**Este proyecto no usó ese `checkout`** (ver «Integración en este proyecto» más abajo). El objetivo de la sesión es guardar datos en el dispositivo con Hive: una caché de los gastos (`GastosRepository`, una caja por usuario) y favoritos de lugares que sobreviven reiniciar la app. Cada bloque comentado trae, justo debajo del `TODO(sesion-07)`, un comentario `// Por qué:` con la explicación.

### Qué descomentar

| Archivo | Qué descomentar | Paso de la práctica | Estado |
|---|---|---|---|
| `lib/controllers/gastos_controller.dart` | En `cargarGastos()`: borrar el bloque que llama a `_api.listarGastos(...)` directamente y descomentar el que llama a `_repository.obtenerGastos()` | Paso 2 | **Hecho, adaptado** (ver «Paso 2 — diferencias con el starter») |
| `lib/screens/gastos_screen.dart` | *(Se escribe a mano, el código está en el instructivo)* el banner «Sin conexión — mostrando tus gastos guardados» con `MaterialBanner` | Paso 2 | **Hecho, adaptado**: envuelve al `RefreshIndicator` que ya existía |
| `lib/controllers/places_controller.dart` | Borrar la versión en memoria de `alternarFavorito` y descomentar el cuerpo real (agrega/quita de `_favoritosBox` y de la lista reactiva `favoritos`) | Paso 3 | **Hecho** (bloque del curso, sin cambios) |
| `lib/controllers/gastos_controller.dart` | En `salir()` (cerrar sesión): borrar el método provisional y descomentar el que además llama a `_repository.vaciar()` | Paso 5 | **Hecho** (bloque del curso + limpieza de `cargandoMas`) |
| `lib/main.dart` | *(Opcional)* Descomentar el `import` y `await SettingsService.abrir();`; y en `GetMaterialApp`, borrar `locale: const Locale('es', 'EC'),` y descomentar `locale: SettingsService.idioma,` | Paso 6 (opcional) | **Hecho** (bloques del curso, sin cambios) |
| `lib/screens/home_screen.dart` | *(Opcional)* Descomentar el `import`; y en el botón de idioma, borrar el bloque `onPressed: () { ... },` y descomentar `onPressed: SettingsService.alternarIdioma,` | Paso 6 (opcional) | **Hecho** (bloques del curso, sin cambios) |

### Integración en este proyecto (Punto de partida y Pasos 1-6)

Como en las Sesiones 5 y 6, se combinó a mano para no perder mejoras propias (Claude Design, playground, `google_fonts`, `tileProvider` del mapa, `RefreshIndicator` de Gastos, comentarios `// Por qué:`, colores del aviso de error y limpieza del worker, distancia junto a la categoría, pruebas propias).

#### Punto de partida y Paso 1 (activo)

- **Tomados del starter (nuevos o sin cambios propios):** `lib/repositories/gastos_repository.dart` (adaptado después en el Paso 2), `lib/services/settings_service.dart` (sin uso hasta el Paso 6), `lib/screens/favorites_screen.dart`, `lib/models/gasto.dart` y `lib/models/place.dart` (`toMap()`/`fromMap()`), `lib/services/gastos_api_service.dart` (suma `obtenerIdUsuario()` → `GET /usuarios/me`; el timeout sigue en 15 s).
- **Combinados:**
  - `main.dart`: `main()` es `async` → `WidgetsFlutterBinding.ensureInitialized()` → `Hive.initFlutter()` → `Hive.openBox<Map>('favoritos')` → `runApp`. No abre ninguna caja de gastos. La pestaña 2 usa `FavoritesScreen`.
  - `gastos_controller.dart`: `_repository`, `desdeCache`, `ultimaSincronizacion`; `entrar()` llama a `_repository.abrirParaUsuario()` justo después del login (caja `gastos_<id>`). `salir()` pasa a `Future<void>`.
  - `places_controller.dart`: `_favoritosBox` y la carga de favoritos guardados en `onInit()`; se conservan el worker `_avisoDeError` (con `onClose`) y el snackbar con colores del tema.
  - `home_screen.dart` y `place_card.dart`: solo comentarios y bloques opcionales comentados.
  - `pubspec.yaml`: `hive: ^2.2.3`, `hive_flutter: ^1.1.0`, `path_provider: ^2.1.4`, conservando `google_fonts: 9.0.0`.
- **Eliminado:** `lib/screens/favorites_placeholder_screen.dart` (todas sus referencias pasaron a `FavoritesScreen`).
- **El token no se guarda en Hive:** sigue solo en el campo `_token` de `GastosApiService`. `grep -rn "Hive\." lib/` muestra solo `main.dart`, `gastos_repository.dart`, `places_controller.dart` y `settings_service.dart`; la caja de gastos guarda solo `gastos`, `total` y `sincronizado` (una prueba lo comprueba).

#### Paso 2 — diferencias con el starter

El repositorio del starter llamaba a `listarGastos(limit: 100)` sin `skip`, devolvía `(List<Gasto>, bool)` y el bloque del controller hacía `totalEnServidor.value = lista.length`: se perdía `X-Total-Count` y, con él, «Cargar más». Se adaptó así:

| Tema | Starter | Este proyecto |
|---|---|---|
| Primera página | `limit: 100`, sin total | `skip=0&limit=20` y el total de `X-Total-Count` (`obtenerGastos(limit:)` devuelve `gastos`, `total`, `desdeCache`) |
| Copia en Hive | Lista + fecha | Lista + **total** + fecha, escritos juntos con un solo `putAll` |
| Recarga exitosa | Reemplaza la copia | Igual: reemplaza la copia (y descarta las páginas extra anteriores) |
| «Cargar más» | Llamaba al servicio directo | Pasa por `obtenerSiguientePagina(mostrados)`: amplía la copia con cada página correcta, descarta ids ya mostrados (sin duplicados) y **nunca** usa el respaldo |
| Fallo de «Cargar más» | `Get.snackbar` | Lo ya mostrado no cambia; el motivo queda en `mensajeCargarMas` y la lista lo muestra junto al botón («Reintentar cargar más»). Se evita una petición doble con `cargandoMas` |
| Con la copia a la vista | — | `hayMas` es `false` (no hay «Cargar más»); `totalEnServidor` conserva el total conocido como metadato |
| Banner | Texto del curso | Mismo texto, icono y «Reintentar»; si la copia es parcial añade «Copia parcial: N de M gastos guardados.»; también aparece con una copia vacía (sobre el `EmptyView`) |
| Pantalla | `Column(banner, Expanded(_buildLista))` | `Column(banner, Expanded(RefreshIndicator(...)))`: se conservan el `RefreshIndicator`, `AlwaysScrollableScrollPhysics` y el botón de recargar |

Igual que en el starter: el respaldo se usa ante falta de conexión, tiempo agotado o 5xx (`statusCode` nulo o ≥ 500) y solo si hay copia; 400/401/403/404 no lo usan y un 401 sigue devolviendo al formulario. Tras una consulta exitosa `desdeCache` vuelve a `false` y el banner desaparece. Nota: el servicio también lanza `ApiException` sin `statusCode` ante un cuerpo JSON inesperado; el repositorio lo trata como falla del servidor (igual que el starter).

#### Paso 3 — favoritos persistentes

- `alternarFavorito` es el bloque del curso tal cual: guarda el `Place` completo con `_favoritosBox.put(lugar.id, lugar.toMap())` o lo borra con `_favoritosBox.delete(lugar.id)`, y actualiza la lista reactiva `favoritos`. Se eliminó la versión en memoria de la Sesión 4; quedan el `TODO(sesion-07)` y su `// Por qué:` actualizado.
- `onInit()` (sin cambios) reconstruye `favoritos` desde la caja con `Place.fromMap(...)`. Como se guarda el lugar completo y no solo su id, un lugar creado a mano —que al reabrir ya no está en Inicio, porque `agregarLugar` vive solo en memoria— sigue apareciendo en Favoritos.
- Sin cambios: el worker `_avisoDeError` y su `dispose()` en `onClose()`, el snackbar de error, la navegación con `Get.to`, la semántica y tooltips del corazón de `PlaceCard` y la fila de categoría y distancia.
- La caja `favoritos` no se separa por usuario ni se borra al cerrar sesión (son lugares públicos, a diferencia de los gastos).

#### Paso 5 — cerrar sesión borra la caja del usuario

- `salir()` es el bloque del curso: `_api.cerrarSesion()` (el token, que solo vivía en memoria, se olvida), `await _repository.vaciar()` (cierra la caja `gastos_<id>` y la borra del disco) y, después, limpia `gastos`, `totalEnServidor`, `desdeCache`, `mensajeCargarMas`, `estado` y `sesionActiva` (vuelve al formulario). Única adición propia: también `cargandoMas = false`, el estado de «Cargar más» que se sumó en el Paso 2.
- No toca la caja `favoritos` (lugares públicos, sobreviven al cierre de sesión) ni el backend.
- Al volver a entrar, `abrirParaUsuario()` abre la caja del id que devuelve `/usuarios/me`: el siguiente usuario empieza sin la copia del anterior.

#### Paso 6 (opcional) — idioma guardado con Hive

- `main.dart`: `import 'services/settings_service.dart';`, `await SettingsService.abrir();` antes de `runApp` (después de la caja `favoritos`) y `locale: SettingsService.idioma` en `GetMaterialApp`; se borró la línea fija `locale: const Locale('es', 'EC')` (no quedan argumentos duplicados). `fallbackLocale` y `translations` siguen igual.
- `home_screen.dart`: `import '../services/settings_service.dart';` y `onPressed: SettingsService.alternarIdioma` en el botón de idioma; se borró el `onPressed: () { ... }` que cambiaba el idioma sin guardarlo. Tooltip `'idioma'.tr` y traducciones sin cambios.
- `lib/services/settings_service.dart` es el del starter, sin cambios: caja `ajustes` con una sola clave (`'idioma'` → `'es'`/`'en'`). Sin preferencia guardada, arranca en español (`es_EC`).
- La caja `ajustes` no depende del usuario: «Cerrar sesión» de Gastos solo borra `gastos_<id>`, así que el idioma se conserva.
- Se mantienen los `TODO(sesion-07): OPCIONAL` (como en los demás pasos) y se actualizaron los `// Por qué:` que describían el código provisional ya borrado.

#### Pruebas

- `test/gastos_controller_test.dart` (41), con su propia carpeta temporal de Hive (las cajas se borran antes de cada prueba y la carpeta al terminar) y `MockClient`:
  - Las 19 de la Sesión 6, adaptadas a `GET /usuarios/me`. Siguen comprobando `skip=0&limit=20` y `X-Total-Count`. Cambiaron por el Paso 2: «sin conexión y sin copia» y «5xx sin copia» (siguen siendo error) y «un fallo de recarga con copia muestra los gastos guardados» (sin red, timeout y 5xx → éxito con `desdeCache`).
  - 3 del Paso 1 (caja `gastos_<id>`, token fuera de Hive, fallo de `/usuarios/me`).
  - 7 nuevas del Paso 2: respaldo tras varias páginas (40 de 45, sin «Cargar más»), reemplazo al refrescar, fallo de página adicional (sin red/timeout/5xx) sin duplicados, página que repite un gasto, copia vacía, 400/403/404 sin respaldo, 401 tras mostrar la copia.
  - 6 del starter: «5xx sin nada en caché», cuatro «Paso 2 — …» y «Paso 5 — cerrar sesión borra la caja del usuario» (todas pasan; la del Paso 5 sin cambios).
  - 1 del Paso 6: cerrar sesión conserva la caja `ajustes` (en disco) con el idioma elegido.
  - 5 nuevas del Paso 5: en disco real (carpeta temporal) el archivo `gastos_1.hive` desaparece y `favoritos.hive` sigue con su contenido, con todo el estado limpio (incluidos los de «Cargar más»); salir con la copia a la vista; tras salir no se envía ningún token; y la secuencia usuario A (id 7, 20 de 45 gastos) → cerrar sesión → usuario B (id 8, sin gastos), con un servidor simulado que responde según el token: B no recibe gastos, total ni copia de A (ni con red ni sin ella) y sus peticiones llevan su propio token.
- `test/widget_test.dart` (82): las 69 de la Sesión 6 adaptadas, «Los favoritos guardados en Hive se cargan al arrancar», 6 del Paso 2 (banner con última sincronización y «Reintentar», deslizar quita el banner, copia parcial «2 de 45» sin «Cargar más», copia vacía con `EmptyView`, sin copia sigue el `ErrorView`, fallo de «Cargar más» con aviso) y 2 del Paso 3 (marcar guarda en la caja y aparece en Favoritos y desmarcar la borra; un lugar agregado a mano sigue en Favoritos al «reabrir» la app). Hive apunta a una carpeta temporal propia, pero las cajas `favoritos` y `gastos_1` se abren **en memoria** (`bytes: Uint8List(0)`): desde los Pasos 2 y 3 cada carga o toque del corazón escribe en la caja, y la E/S real de disco no termina dentro del reloj simulado de `testWidgets` (además, `clear()`/`close()` esperan esas escrituras y bloquearían el `tearDown`). La escritura en disco la cubren `gastos_controller_test.dart` y `favoritos_persistencia_test.dart`. Excepción, Paso 5: «Cerrar sesión borra la caja del disco, conserva favoritos y vuelve al formulario» no puede usar `gastos_1` en memoria (una caja en memoria no admite `deleteFromDisk()`, que es lo que hace `vaciar`); usa la caja en disco dentro de la carpeta temporal y ejecuta `entrar` y `salir` del controller con `tester.runAsync` (la E/S de disco no avanza dentro del reloj simulado; se probó dejarla avanzar con `idle()`/`pump()` y la apertura de la caja no progresa). La pantalla se comprueba con `pump`: vuelve el formulario, el archivo `gastos_1.hive` desaparece y el favorito sigue. Esa prueba abre el menú «⋮» y comprueba que ofrece «Cerrar sesión», pero **no** toca la opción: la conexión «opción del menú → `controller.salir()`» (sin cambios desde la Sesión 6) queda para la prueba manual. No se añadió ningún caso especial al código de producción.
- `test/favoritos_persistencia_test.dart` (5, Paso 3): caja `favoritos` **en disco**, en su propia carpeta temporal (la caja se borra tras cada prueba y la carpeta al terminar; nunca se usa la carpeta de datos de la app). Comprueba que la caja está en esa carpeta, que marcar guarda el lugar completo, que cerrar y reabrir la caja con un controller nuevo lo recupera (y que el anterior se cerró), que desmarcar lo borra del almacenamiento y que un lugar agregado a mano se recupera aunque no esté en la lista inicial. Son `test()` normales, sin reloj simulado. Nota: el controller se registra con `Get.put<PlacesController>(...)`; sin el tipo explícito, dentro de una función `async` la clave sería `FutureOr<PlacesController>`.
- `test/widget_test.dart`, Paso 6: la caja `ajustes` se abre en memoria en `setUpAll` y se vacía tras cada prueba (ninguna prueba hereda el idioma de otra). 3 pruebas nuevas en «Idioma con GetX»: sin preferencia arranca en español; el botón guarda `'en'` y luego `'es'`; al «reiniciar» (desmontar, `Get.reset()`, `Get.locale = null`, volver a montar) arranca en inglés y, tras volver a español, en español. Reutilizan `tocarIdioma`, que viene de la Sesión 4 y espera 50 ms reales dentro de `runAsync` para que termine el reensamblado de `Get.updateLocale`.
- `test/ajustes_persistencia_test.dart` (5, Paso 6): caja `ajustes` **en disco**, en su propia carpeta temporal (se borra tras cada prueba y la carpeta al terminar). Comprueba la carpeta, el valor inicial (español, sin clave guardada), elegir inglés y recuperarlo al cerrar y reabrir la caja, volver a español y recuperarlo, y que la caja solo guarda `idioma`. Las que tocan el botón son `testWidgets` con la E/S dentro de `tester.runAsync`, porque `Get.updateLocale` solo funciona con el motor de pruebas activo.
- **Ninguna prueba falla a propósito**: desde el Paso 5, `flutter test` termina con todas pasando.
- El tiempo agotado se simula haciendo que el `MockClient` lance `TimeoutException`, la misma excepción que produce `.timeout(...)`; no se espera 15 s.

### Estado final de la Sesión 7

#### Comprobado a mano en el emulador

Contra el backend local (`proyecto-curso-spec-kit` con Docker), por el equipo:

- **Sin conexión (Pasos 2 y 4):** con el backend detenido, los tres gastos del usuario siguen visibles con el banner «Sin conexión — mostrando tus gastos guardados» y la hora de la última sincronización; al volver a encender el backend y recargar, el aviso desaparece.
- **Favoritos (Pasos 3 y 5):** sobreviven a cerrar la app por completo y volver a abrirla. El lugar propio («Mi lugar de prueba») sigue en Favoritos y ya no aparece en Inicio, como pide el curso.
- **Cambio de usuario (Paso 5):** la segunda cuenta tiene cero gastos y no ve los de la primera; los favoritos se mantienen.
- **Archivos en el dispositivo (Paso 5):** tras «Cerrar sesión», `adb shell run-as com.example.exploraec ls app_flutter` confirmó que `gastos_3.hive` desaparece y `favoritos.hive` permanece.
- **Idioma (Paso 6):** el inglés sobrevive al reinicio y al cierre de sesión de Gastos; volver a español también se conserva tras reiniciar.

#### Pruebas automáticas

`flutter analyze` sin incidencias y `flutter test` con **133 pruebas aprobadas**: `gastos_controller_test.dart` (41), `widget_test.dart` (82), `favoritos_persistencia_test.dart` (5) y `ajustes_persistencia_test.dart` (5). Todas usan HTTP simulado y Hive en carpetas temporales, sin backend real.

#### Respuestas de reflexión

1. **¿Qué guardamos y qué no?** *(implementado)* Guardamos en Hive una copia de los gastos (lista, total y fecha de sincronización) y las preferencias del usuario (favoritos de lugares e idioma). El token **no** se guarda en Hive: sigue solo en memoria (campo `_token` de `GastosApiService`); su almacenamiento seguro es de la Sesión 8.
2. **¿Por qué la caché es por usuario y los favoritos no?** *(implementado)* La caché de gastos son datos personales y Hive guarda sin cifrar: se separa por usuario (`gastos_<id>`, con el id de `/usuarios/me`) y se elimina al cerrar sesión por privacidad en un teléfono compartido. Los favoritos son decisiones locales sobre lugares públicos y permanecen en el dispositivo.
3. **¿Y un gasto creado sin conexión?** *(diseño futuro, **no implementado** en esta sesión; la caché actual es solo de lectura)* Necesitaría una cola local de operaciones pendientes, un identificador provisional único y un estado «pendiente de sincronizar». Al aceptarlo el servidor, se asociaría su identificador definitivo. Si lo rechazara (por ejemplo, por el límite de 500 por categoría), se conservaría como fallido con el motivo, para corregirlo o descartarlo, sin mostrarlo nunca como sincronizado.
4. **¿Otra opción para el idioma?** *(reflexión)* Para un solo valor simple también serviría `SharedPreferences`; aquí reutilizamos Hive porque ya forma parte del proyecto (una dependencia menos y el mismo patrón de cajas).

#### `TODO(sesion-07)` que quedan en el código

Son **comentarios del curso** que se conservan a propósito, como en la Sesión 6: el `TODO` y su `// Por qué:` se quedan; el código provisional que describían ya se borró. **No hay funcionalidad pendiente detrás de ninguno:**

| Archivo | TODO | Estado |
|---|---|---|
| `lib/controllers/gastos_controller.dart` | `cargarGastos()` (Paso 2) | Hecho |
| `lib/controllers/gastos_controller.dart` | `salir()` (Paso 5) | Hecho |
| `lib/controllers/places_controller.dart` | `alternarFavorito` (Paso 3) | Hecho |
| `lib/main.dart` (3) y `lib/screens/home_screen.dart` (2) | `OPCIONAL` (Paso 6) | Hecho |

Los `TODO(sesion-02)` de `lib/playground/` son ejercicios de la Sesión 2 que no forman parte de la app; esta sesión no los toca.

#### Pendientes reales (fuera de esta sesión)

- Token solo en memoria: al reabrir la app hay que volver a iniciar sesión, y sin backend no se puede entrar a ver la caché (almacenamiento seguro en la Sesión 8).
- Crear o editar gastos sin conexión: solo diseño (respuesta 3).
- Tráfico HTTP sin cifrar (`usesCleartextTraffic`): solo para desarrollo, heredado de la Sesión 6.
- Detalles de comportamiento a tener presentes: un cuerpo JSON inesperado del servidor (`ApiException` sin `statusCode`) también usa la copia, igual que en el starter; el fallo de «Cargar más» se avisa junto al botón en lugar de con un snackbar.

### Historial — Sesión 6

Notas de la Sesión 6, conservadas tal como quedaron (el estado de Favoritos y de las pruebas descrito aquí es el de esa sesión).

Punto de partida: ExploraEC con lugares y mapa de las Sesiones 1-5 intactos, más la sección nueva **Gastos**, que habla con el backend de gastos del módulo anterior. Tráela con:

```bash
git fetch starter
git checkout starter/sesion-06 -- lib pubspec.yaml PLACEHOLDERS.md
flutter pub get
```

Los cambios nativos (permiso de internet y tráfico HTTP en claro) se hacen **a mano** en tu proyecto, porque `android/` no vive en este repo (ver `README.md`).

#### Qué descomentar

| Archivo | Qué descomentar | Paso de la práctica |
|---|---|---|
| `lib/controllers/gastos_controller.dart` | `entrar(...)` (registro → login → listar) y `cargarGastos()` | Paso 7 |
| `lib/services/gastos_api_service.dart` | Cambiar `.timeout(const Duration(seconds: 15))` por 1 ms y devolverlo a 15 s | Paso 9 |
| `lib/screens/gastos_screen.dart` | *(Opcional)* `RefreshIndicator` (borrar el `return _buildLista(...)` y descomentar el bloque) | Paso 10 |

#### Pruebas

`test/gastos_controller_test.dart` prueba el controller con un servidor falso (`MockClient`): no necesita el backend. En el starter, sus 7 pruebas fallan hasta completar el Paso 7. **En este proyecto el Paso 7 ya está hecho**: el archivo trae esas 7 más 12 propias (19 en total) y todas pasan. Ejecutarlas: `flutter test`.

#### Integración en este proyecto (Paso 5)

Como en la Sesión 5, este proyecto **no** usó `git checkout starter/sesion-06 -- lib pubspec.yaml`: habría eliminado mejoras propias (Claude Design, playground, `google_fonts`, `tileProvider` del mapa, comentarios `// Por qué:`, colores y guardado de avisos, limpieza del worker, distancia junto a la categoría). Se combinó a mano:

- **Tomados tal cual del starter:** `lib/config/api_config.dart`, `lib/controllers/gastos_controller.dart`, `lib/models/gasto.dart`, `lib/screens/gastos_screen.dart`, `lib/services/api_exception.dart`, `lib/services/gastos_api_service.dart` (se trajeron con sus `TODO(sesion-06)` inactivos; los Pasos 7 y 10 los activaron después y en `lib/` ya no queda ninguno).
- **Combinados:** `PlacesBinding` (`Get.lazyPut(() => GastosController())`), `main.dart` (cuarta pestaña Gastos y `BottomNavigationBarType.fixed`), `AppTranslations` (clave `gastos`: Gastos / Expenses) y `pubspec.yaml` (`http: ^1.2.2`, conservando `google_fonts: 9.0.0` y las dependencias de la Sesión 5).
- **Pruebas (Paso 7):** `test/gastos_controller_test.dart` incorpora las 7 pruebas del starter más comprobaciones propias (orden registro → login → listado, formatos JSON/formulario, cabecera Bearer, errores que cortan el flujo, `autenticando`, total del servidor y conservación de datos ante un fallo de recarga), todas con `MockClient`, sin backend real.
- **Android (a mano):** `AndroidManifest.xml` tiene `android.permission.INTERNET` y `android:usesCleartextTraffic="true"` en `<application>`, además de los permisos de ubicación de la Sesión 5. **El tráfico HTTP sin cifrar es solo para desarrollo** (backend local en `http://10.0.2.2:8000`); una app publicada debe usar HTTPS y quitar ese atributo o limitarlo con `network_security_config`.

##### Estado esperado tras el Paso 7

La pestaña Gastos muestra el formulario; **Entrar** ejecuta registro (un 400 por correo existente se ignora) → login → listado contra el backend y pasa a la lista con los estados cargando/vacío/error. Un 401 al listar vuelve al formulario con el motivo; un fallo de recarga conserva en el controller los gastos ya cargados. El timeout definitivo es de 15 s: el Paso 9 se probó a mano con 1 ms (mensaje de tiempo agotado) y se restauró; después de restaurarlo fue necesario volver a iniciar sesión desde el formulario. Lugares, mapa, favoritos e idioma siguen como en la Sesión 5.

##### Paso 10 (opcional) — deslizar para actualizar: activado

En `GastosScreen` la lista va dentro de un `RefreshIndicator` con `onRefresh: controller.cargarGastos` (bloque del curso). El `ListView` ya usaba `AlwaysScrollableScrollPhysics`, así que el gesto funciona aunque la lista tenga pocos gastos y no llene la pantalla. Mientras recarga se ve el `LoadingView` (el estado pasa a `cargando`), y en los estados vacío y error no hay lista que deslizar: se usa el botón de recargar o "Reintentar". El botón de recargar de la barra y "Cargar más" siguen igual. El mini-reto del aviso al terminar no está implementado.

Prueba: `widget_test.dart` desliza la lista con un solo gasto y comprueba que se vuelve a pedir `GET /gastos/?skip=0&limit=20` y que aparece el gasto nuevo, con un backend simulado y sin conexiones reales.

##### Ajustes propios heredados de la Sesión 5 (se conservan)

- `MapScreen` acepta un `tileProvider` opcional; `null` (lo que usa la app) mantiene el proveedor de red de OpenStreetMap. Las pruebas pasan uno local para no descargar teselas.
- La distancia de `PlaceCard` va en la misma línea que la categoría, para no desbordar las celdas estrechas de la grilla (`childAspectRatio: 2.2`).

#### Estado final de la Sesión 6

- **Comprobado a mano en el emulador** contra el backend local (`proyecto-curso-spec-kit` con Docker): registro e inicio de sesión, lista vacía y con tres gastos, desconexión del backend y recuperación, sesión inválida con regreso al formulario, validación de contraseña corta, paginación con `X-Total-Count`, timeout (Paso 9) y deslizar para actualizar (Paso 10).
- **Comprobado en PostgreSQL** (consultas de solo lectura): los tres gastos del usuario de práctica y que el usuario rechazado por contraseña corta no existe.
- **Pruebas automáticas:** `flutter analyze` sin incidencias y 88 pruebas aprobadas (`widget_test.dart` y `gastos_controller_test.dart`), sin backend real ni descarga de teselas.
- **Pendiente para otras sesiones:** el token vive solo en memoria (se pierde al reiniciar la app; almacenamiento seguro en la Sesión 8) y el tráfico HTTP sin cifrar es solo para desarrollo.

