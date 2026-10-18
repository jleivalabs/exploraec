import 'dart:io';

import 'package:exploraec/services/settings_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:hive/hive.dart';

/// Idioma guardado — Sesión 7, Paso 6 (opcional). La caja `ajustes` vive en
/// disco, en una carpeta temporal propia de este archivo, y se cierra y se
/// vuelve a abrir de verdad, como al reiniciar la app.
///
/// `alternarIdioma` llama a `Get.updateLocale`, que reconstruye la app con el
/// motor de pruebas de Flutter y solo funciona dentro de `testWidgets`. Por
/// eso esas pruebas son `testWidgets` y toda su E/S de disco va dentro de
/// `tester.runAsync` (la zona real): dentro del reloj simulado no avanzaría.
void main() {
  late Directory carpetaHive;

  /// Como al arrancar la app: `main()` abre la caja antes de `runApp` y
  /// `GetMaterialApp` toma `SettingsService.idioma` como `locale`.
  Future<Locale> arrancar() async {
    await SettingsService.abrir();
    final idioma = SettingsService.idioma;
    Get.locale = idioma;
    return idioma;
  }

  /// Como al cerrar la app: `close()` espera las escrituras pendientes.
  Future<void> cerrar() async {
    await Hive.box('ajustes').close();
    Get.locale = null;
  }

  setUpAll(() {
    carpetaHive = Directory.systemTemp.createTempSync('exploraec_hive_ajustes_');
    Hive.init(carpetaHive.path);
  });

  tearDown(() async {
    Get.locale = null;
    // Solo afecta a `carpetaHive`: cada prueba parte sin preferencia.
    await Hive.deleteBoxFromDisk('ajustes');
  });

  tearDownAll(() async {
    await Hive.close();
    if (carpetaHive.existsSync()) carpetaHive.deleteSync(recursive: true);
  });

  test('la caja está en la carpeta temporal, no en la de la app', () async {
    await arrancar();
    expect(Hive.box('ajustes').path, startsWith(carpetaHive.path));
  });

  test('sin preferencia guardada, arranca en español (es_EC)', () async {
    final idioma = await arrancar();
    expect(idioma, const Locale('es', 'EC'));
    expect(Hive.box('ajustes').get('idioma'), isNull);
  });

  testWidgets('elegir inglés lo guarda y se recupera al reabrir', (tester) async {
    await tester.runAsync(() async {
      await arrancar();
      SettingsService.alternarIdioma();
      expect(Get.locale, const Locale('en', 'US'));
      expect(Hive.box('ajustes').get('idioma'), 'en');
      await cerrar();

      expect(Hive.isBoxOpen('ajustes'), isFalse);
      final idioma = await arrancar();
      expect(idioma, const Locale('en', 'US'));
    });
  });

  testWidgets('volver a español también se guarda y se recupera al reabrir', (tester) async {
    await tester.runAsync(() async {
      await arrancar();
      SettingsService.alternarIdioma(); // es -> en
      await cerrar();
      expect(await arrancar(), const Locale('en', 'US'));

      SettingsService.alternarIdioma(); // en -> es
      expect(Get.locale, const Locale('es', 'EC'));
      expect(Hive.box('ajustes').get('idioma'), 'es');
      await cerrar();

      expect(await arrancar(), const Locale('es', 'EC'));
    });
  });

  testWidgets('la caja solo guarda el idioma (ni token ni otros datos)', (tester) async {
    await tester.runAsync(() async {
      await arrancar();
      SettingsService.alternarIdioma();
      expect(Hive.box('ajustes').keys.toList(), ['idioma']);
    });
  });
}
