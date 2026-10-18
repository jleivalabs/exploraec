import 'dart:io';

import 'package:exploraec/controllers/places_controller.dart';
import 'package:exploraec/models/place.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:hive/hive.dart';

/// Favoritos persistentes — Sesión 7, Paso 3. A diferencia de
/// `widget_test.dart` (caja en memoria), aquí la caja `favoritos` vive en
/// disco, en una carpeta temporal propia de este archivo: se cierra y se
/// vuelve a abrir de verdad, como al cerrar y reabrir la app. Son pruebas
/// `test()` normales (sin reloj simulado), así la E/S de Hive termina sola.
void main() {
  late Directory carpetaHive;
  final lugaresOriginales = List<Place>.of(lugaresEjemplo);

  final propio = Place(
    id: 'lugar-propio-prueba',
    nombre: 'Mi lugar de prueba',
    categoria: 'Pruebas',
    descripcion: 'Lugar sintético creado por la prueba.',
    lat: -0.2201,
    lng: -78.5123,
  );

  Box<Map> caja() => Hive.box<Map>('favoritos');

  /// Lo que hace `main()` al arrancar: abrir la caja antes de crear el
  /// controller (que la lee en `onInit()`).
  Future<PlacesController> arrancar() async {
    await Hive.openBox<Map>('favoritos');
    // Tipo explícito: dentro de una función `async`, `Get.put(...)` en el
    // `return` inferiría `FutureOr<PlacesController>` como clave, y luego
    // `Get.delete<PlacesController>()` no lo encontraría.
    return Get.put<PlacesController>(PlacesController());
  }

  /// Simula cerrar la app: se descarta el controller (su `onClose()` libera
  /// el worker) y se cierra la caja. `close()` espera a que terminen las
  /// escrituras pendientes, así lo marcado queda en disco.
  Future<void> cerrar() async {
    await Get.delete<PlacesController>();
    await caja().close();
    lugaresEjemplo
      ..clear()
      ..addAll(lugaresOriginales);
  }

  setUpAll(() {
    carpetaHive = Directory.systemTemp.createTempSync('exploraec_hive_favoritos_');
    Hive.init(carpetaHive.path);
    Get.isLogEnable = false;
  });

  setUp(() => Get.testMode = true);

  tearDown(() async {
    Get.reset();
    lugaresEjemplo
      ..clear()
      ..addAll(lugaresOriginales);
    // Solo afecta a `carpetaHive`: cada prueba parte sin caja guardada.
    await Hive.deleteBoxFromDisk('favoritos');
  });

  tearDownAll(() async {
    await Hive.close();
    if (carpetaHive.existsSync()) carpetaHive.deleteSync(recursive: true);
  });

  test('la caja está en la carpeta temporal, no en la de la app', () async {
    await arrancar();
    expect(caja().path, startsWith(carpetaHive.path));
  });

  test('marcar un lugar lo guarda en la caja y aparece en favoritos', () async {
    final c = await arrancar();
    final lugar = lugaresEjemplo.first;
    expect(c.favoritos, isEmpty);

    c.alternarFavorito(lugar);
    expect(c.favoritos.map((p) => p.id).toList(), [lugar.id]);
    expect(c.esFavorito(lugar), isTrue);
    expect(Map<String, dynamic>.from(caja().get(lugar.id)!), lugar.toMap());
  });

  test('cerrar y reabrir la caja con un controller nuevo recupera el favorito', () async {
    final antes = await arrancar();
    final lugar = lugaresEjemplo[1];
    antes.alternarFavorito(lugar);
    await cerrar();
    expect(antes.isClosed, isTrue, reason: 'onClose() corrió: el worker quedó liberado');
    expect(Hive.isBoxOpen('favoritos'), isFalse);

    final despues = await arrancar();
    expect(identical(despues, antes), isFalse);
    expect(despues.favoritos, hasLength(1));
    final recuperado = despues.favoritos.single;
    expect(recuperado.toMap(), lugar.toMap());
    expect(despues.esFavorito(lugar), isTrue);
    expect(despues.totalFavoritos, 1);
  });

  test('desmarcar lo elimina también del almacenamiento', () async {
    final c = await arrancar();
    final marcado = lugaresEjemplo[0];
    final otro = lugaresEjemplo[1];
    c.alternarFavorito(marcado);
    c.alternarFavorito(otro);
    c.alternarFavorito(marcado); // lo desmarca
    expect(caja().containsKey(marcado.id), isFalse);
    expect(caja().keys.toList(), [otro.id]);
    await cerrar();

    final despues = await arrancar();
    expect(despues.esFavorito(marcado), isFalse);
    expect(despues.favoritos.map((p) => p.id).toList(), [otro.id]);
  });

  test('un lugar agregado a mano se recupera en favoritos aunque no esté en la lista inicial', () async {
    final c = await arrancar();
    c.agregarLugar(propio);
    c.alternarFavorito(propio);
    await cerrar();

    // Al «reabrir», la lista inicial ya no tiene el lugar propio (vive solo
    // en memoria), pero el favorito se reconstruye desde Hive con Place.fromMap.
    expect(lugaresEjemplo.any((p) => p.id == propio.id), isFalse);
    final despues = await arrancar();
    expect(despues.favoritos, hasLength(1));
    expect(despues.favoritos.single.toMap(), propio.toMap());
    expect(despues.esFavorito(propio), isTrue);
  });
}
