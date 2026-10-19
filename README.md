# ExploraEC

App Flutter (Android) para explorar lugares de Ecuador y llevar los gastos de un viaje, con un asistente de IA (ExploraIA) que responde preguntas sobre esos gastos. Es el proyecto de práctica del curso de Flutter y Dart de CEDIA (Sesiones 1 a 10).

> **Proyecto de práctica, no de producción.** El APK se firma con la clave de debug y se conecta por HTTP sin cifrar a direcciones del emulador (`10.0.2.2`).

## Capturas de pantalla

*Pendiente:* guardar en `docs/capturas/` al menos la lista de gastos, el inicio de sesión y el Asistente, y enlazarlas aquí.

## Qué incluye

- [x] Registro, inicio y cierre de sesión con JWT contra el backend de gastos; el token se guarda en `flutter_secure_storage` y la sesión se restaura al reabrir la app.
- [x] Lista de gastos con estados de carga, vacío y error, paginación de 20 en 20 (`X-Total-Count`), deslizar para actualizar y filtro por categoría.
- [x] Copia local de los gastos por usuario (Hive): sin conexión se muestran con un aviso y la hora de la última sincronización.
- [x] Persistencia local que sobrevive al reinicio: favoritos, idioma (español/inglés) y caché de gastos.
- [x] Datos remotos protegidos: crear, editar y eliminar gastos exige el token; un 401 cierra la sesión y vuelve al inicio de sesión.
- [x] Asistente con IA mediante un proxy propio (`mock-server/`), sin claves en la app.
- [x] Estado compartido con GetX (controladores, *bindings* y traducciones).
- [x] Manejo de errores no esperados (`ReporteErrores`), CI en cada push y PR, y Release automático del APK.

## Cómo ejecutarla

Requisitos: Flutter 3.47.5 (Dart 3.13.4), Android SDK con un emulador (minSdk 24), Node.js 18 o superior para el proxy, y el backend de gastos del curso (`proyecto-curso-spec-kit`, con Docker).

1. **Backend de gastos:** levántalo siguiendo las instrucciones de su repositorio. Debe responder en `http://localhost:8000`.

2. **Proxy del Asistente** (opcional; sin él, el resto de la app funciona). Sin `GEMINI_API_KEY` responde en modo reglas, sin internet. Detalles y modo Gemini en [`mock-server/README.md`](mock-server/README.md).

   ```powershell
   cd mock-server
   $env:PORT="3001"
   node mock-server.js
   ```

3. **App:**

   ```bash
   flutter pub get
   flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8000 --dart-define=LLM_BACKEND_URL=http://10.0.2.2:3001
   ```

4. **Direcciones por entorno.** En el emulador Android, `10.0.2.2` es el `localhost` del computador. Los valores por defecto son `http://10.0.2.2:8000` para el backend y `http://10.0.2.2:3000` para el proxy; por eso se indica `3001` arriba. En un dispositivo físico usa la IP del computador en la red local con los mismos `--dart-define`.

## Verificación

```bash
flutter analyze
flutter test
```

Las pruebas no necesitan backend, emulador ni Gemini: usan servidores falsos y cajas de Hive en memoria. Último resultado registrado: análisis sin incidencias y 223 pruebas aprobadas.

## APK

Descárgalo desde [Releases](https://github.com/jleivalabs/exploraec/releases/tag/v1.0.0) (`app-release.apk`, versión `v1.0.0`). Lo genera [`release-apk.yml`](.github/workflows/release-apk.yml) al subir una etiqueta `v*`: primero ejecuta el análisis y las pruebas, y luego compila con `API_BASE_URL` y `LLM_BACKEND_URL` (variables del repositorio o, si no existen, las direcciones del emulador con los puertos 8000 y 3001).

Para probarlo, instálalo en el emulador con el backend encendido. Si ya tenías instalada una versión firmada en otra máquina, desinstálala antes, porque las firmas no coinciden:

```bash
adb uninstall com.example.exploraec
adb install app-release.apk
```

La integración continua ([`ci.yml`](.github/workflows/ci.yml)) ejecuta `flutter analyze` y `flutter test` en cada push, en cada PR y a mano.

## Arquitectura

```text
lib/
  screens/       pantallas (solo interfaz)
  widgets/       piezas reutilizables (cargando, vacío, error, sin sesión)
  controllers/   estado con GetX (sesión, gastos, lugares)
  services/      HTTP con dio, token seguro, ajustes, asistente
  repositories/  caché local de gastos con Hive, una caja por usuario
  models/        gastos, lugares, usuario y resumen
  i18n/          textos en español e inglés
  utils/         validadores y reporte de errores
mock-server/     proxy del Asistente (Node), fuera de la app
```

**Cómo viaja un gasto:** `GastosScreen` solo observa a `GastosController`. El controlador pide la página a `GastosApiService` (dio con el token añadido por un interceptor). Si la respuesta llega, la guarda en la caja Hive del usuario mediante `GastosRepository` y actualiza la lista. Si falla la conexión, muestra la copia local con un aviso. Cada operación lleva una marca de sesión: si la persona cerró sesión o cambió de cuenta mientras esperaba, el resultado se descarta.

## Decisión técnica propia

<!-- Completar con tus palabras. Un candidato: la marca de sesión que descarta las respuestas que llegan después de cerrar sesión o de cambiar de usuario, junto con una caja de Hive por usuario para que una cuenta nunca vea los gastos de otra. -->

## Tecnologías

| Paquete | Para qué |
|---|---|
| `get` | Estado, navegación, inyección de dependencias y traducciones |
| `dio` | HTTP con el backend y el proxy, interceptores de token y 401 |
| `flutter_secure_storage` | Token de sesión |
| `hive`, `hive_flutter`, `path_provider` | Favoritos, ajustes y caché de gastos |
| `flutter_map`, `geolocator`, `permission_handler` | Mapa y posición del usuario |
| `google_fonts` | Tipografía |
| `flutter_localizations` | Textos de Flutter en el idioma de la app |

## Seguridad

- No hay claves ni secretos en el repositorio (`.env` está en `.gitignore`).
- El token se guarda con almacenamiento seguro y no se escribe en los registros. Al cerrar sesión se borran el token y la copia local de los gastos.
- La clave de Gemini, si se usa, vive solo en el entorno del proxy. La app solo conoce la dirección del proxy, y al proxy solo viaja el resumen por categoría.
- Android tiene la copia de seguridad desactivada (`allowBackup="false"` y `dataExtractionRules`).
- Límites conocidos: firma de debug, HTTP sin cifrar y direcciones de emulador. Para producción harían falta una clave de firma propia, HTTPS y la dirección real del backend.

## Créditos y licencias

- Base del proyecto: repositorio de práctica del curso de CEDIA ([Patricio-CEDIA/exploraec-app](https://github.com/Patricio-CEDIA/exploraec-app)).
- Mapas: © colaboradores de OpenStreetMap (ODbL).
- Paquetes de Dart y Flutter bajo sus respectivas licencias (ver `pubspec.lock`).
