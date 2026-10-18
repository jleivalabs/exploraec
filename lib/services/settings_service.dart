import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:hive/hive.dart';

/// Ajustes del usuario que sobreviven reiniciar la app — Sesión 7 (Paso 6,
/// opcional). Hoy guarda uno solo: el idioma elegido con el botón de
/// traducir de Inicio (Sesión 4). Es una caja de Hive de clave-valor
/// simple (`'idioma'` → `'es'` o `'en'`), sin adaptadores ni serialización:
/// el valor ya es un `String`.
class SettingsService {
  SettingsService._();

  static const _nombreCaja = 'ajustes';
  static const _claveIdioma = 'idioma';

  static const _es = Locale('es', 'EC');
  static const _en = Locale('en', 'US');

  /// Abre la caja. Se llama una sola vez desde `main()`, antes de `runApp`.
  static Future<void> abrir() => Hive.openBox(_nombreCaja);

  /// Idioma guardado, o español si nunca se eligió ninguno.
  static Locale get idioma {
    final guardado = Hive.box(_nombreCaja).get(_claveIdioma, defaultValue: 'es');
    return guardado == 'en' ? _en : _es;
  }

  /// Cambia el idioma de toda la interfaz (GetX) y lo guarda en Hive.
  static void alternarIdioma() {
    final nuevo = Get.locale?.languageCode == 'es' ? _en : _es;
    Get.updateLocale(nuevo);
    Hive.box(_nombreCaja).put(_claveIdioma, nuevo.languageCode);
  }

  // ---- Sesión 8 (Paso 4): metadato de limpieza ----
  // Último id de usuario confirmado por `GET /usuarios/me`. Sirve SOLO para
  // encontrar la caja `gastos_<id>` que hay que borrar si una sesión
  // restaurada resulta caducada (401) y nadie abrió esa caja. Nunca se usa
  // para autenticar ni para mostrar gastos. Si la caja `ajustes` no está
  // abierta (`main()` la abre antes de `runApp`), no se lee ni se guarda.
  static const _claveUltimoUsuario = 'ultimo_usuario_id';

  static int? get ultimoUsuarioId {
    if (!Hive.isBoxOpen(_nombreCaja)) return null;
    final id = Hive.box(_nombreCaja).get(_claveUltimoUsuario);
    return id is int ? id : null;
  }

  static Future<void> recordarUltimoUsuario(int id) async {
    if (Hive.isBoxOpen(_nombreCaja)) await Hive.box(_nombreCaja).put(_claveUltimoUsuario, id);
  }

  static Future<void> olvidarUltimoUsuario() async {
    if (Hive.isBoxOpen(_nombreCaja)) await Hive.box(_nombreCaja).delete(_claveUltimoUsuario);
  }
}
