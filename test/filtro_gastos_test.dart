import 'dart:io';
import 'dart:typed_data';

import 'package:exploraec/controllers/auth_controller.dart';
import 'package:exploraec/controllers/gastos_controller.dart';
import 'package:exploraec/i18n/app_translations.dart';
import 'package:exploraec/repositories/gastos_repository.dart';
import 'package:exploraec/screens/gastos_screen.dart';
import 'package:exploraec/services/api_client.dart';
import 'package:exploraec/services/gastos_api_service.dart';
import 'package:exploraec/widgets/empty_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:hive/hive.dart';

import 'helpers/servidor_gastos_falso.dart';

/// Filtro por categoría en Gastos — Sesión 10, Paso 7. Sin backend real: el
/// servidor falso de `dio` y una caja de gastos EN MEMORIA (mismo patrón que
/// `widget_test.dart`): ninguna escritura real de Hive dentro del reloj simulado.
///
/// `dio` ejecuta cada interceptor dentro de `Future(() …)` (un temporizador de
/// duración cero), que en el reloj simulado de `testWidgets` solo se dispara al
/// avanzar el reloj. Por eso las operaciones que se esperan directamente
/// (iniciar o cerrar sesión, carga inicial, eliminar) van en `tester.runAsync`;
/// los toques seguidos de `pumpAndSettle` sí avanzan el reloj.

// Datos sintéticos.
const _correoA = 'a@ejemplo.com';
const _correoB = 'b@ejemplo.com';
const _clave = 'clave-1234';

Map<String, dynamic> _gasto(int id, String categoria) =>
    {'id': id, 'descripcion': 'Gasto $id', 'monto': 1 + id, 'categoria': categoria, 'fecha': '2026-10-18'};

/// Repositorio real con la caja `gastos_<id>` en memoria (patrón existente).
class _RepositorioEnMemoria extends GastosRepository {
  _RepositorioEnMemoria(super.api);

  @override
  Future<bool> abrirParaUsuario(int idUsuario) async {
    final nombre = 'gastos_$idUsuario';
    if (!Hive.isBoxOpen(nombre)) await Hive.openBox(nombre, bytes: Uint8List(0));
    return super.abrirParaUsuario(idUsuario);
  }

  @override
  Future<bool> vaciar() async {
    try {
      return await super.vaciar();
    } on UnsupportedError {
      return true; // caja en memoria: ya quedó cerrada, no hay archivo
    }
  }
}

void main() {
  late Directory carpetaHive;
  late ServidorGastosFalso servidor;
  late AuthController auth;

  setUpAll(() {
    carpetaHive = Directory.systemTemp.createTempSync('exploraec_hive_filtro_');
    Hive.init(carpetaHive.path);
    Get.isLogEnable = false;
  });
  tearDown(() async {
    Get.reset();
    Get.locale = null;
    Get.clearTranslations();
    for (final id in [1, 2]) {
      if (Hive.isBoxOpen('gastos_$id')) await Hive.box('gastos_$id').close();
    }
  });
  tearDownAll(() async {
    await Hive.close();
    if (carpetaHive.existsSync()) carpetaHive.deleteSync(recursive: true);
  });

  /// Monta la pantalla de Gastos (como en la app) e inicia sesión con A.
  Future<GastosController> entrar(
    WidgetTester tester, {
    required List<Map<String, dynamic>> gastosA,
    int? totalA,
    bool paginar = false,
    List<Map<String, dynamic>> gastosB = const [],
    Locale idioma = const Locale('es', 'EC'),
  }) async {
    FlutterSecureStorage.setMockInitialValues({});
    servidor = ServidorGastosFalso({
      _correoA: UsuarioFalso(id: 1, password: _clave, gastos: List.of(gastosA), total: totalA),
      _correoB: UsuarioFalso(id: 2, password: _clave, gastos: List.of(gastosB)),
    })
      ..paginar = paginar;
    Get.put<ApiClient>(ApiClient(dio: servidor.crearDio()), permanent: true);
    auth = Get.put<AuthController>(AuthController(), permanent: true);
    Get.lazyPut<GastosController>(
        () => GastosController(repositorio: _RepositorioEnMemoria(GastosApiService(Get.find<ApiClient>()))));
    await tester.pumpWidget(GetMaterialApp(
      translations: AppTranslations(),
      locale: idioma,
      fallbackLocale: const Locale('es', 'EC'),
      home: const GastosScreen(),
    ));
    final g = Get.find<GastosController>();
    await tester.runAsync(() async {
      await auth.iniciarSesion(_correoA, _clave);
      await g.cargaInicial;
    });
    await tester.pumpAndSettle();
    return g;
  }

  List<String> chips(WidgetTester tester) => tester
      .widgetList<ChoiceChip>(find.byType(ChoiceChip))
      .map((c) => (c.label as Text).data!)
      .toList();

  String? chipSeleccionado(WidgetTester tester) {
    final elegidos = tester.widgetList<ChoiceChip>(find.byType(ChoiceChip)).where((c) => c.selected);
    return elegidos.isEmpty ? null : (elegidos.single.label as Text).data;
  }

  List<String> titulosVisibles(WidgetTester tester) => tester
      .widgetList<ListTile>(find.byType(ListTile))
      .map((t) => (t.title as Text).data!)
      .toList();

  Future<void> tocarChip(WidgetTester tester, String etiqueta) async {
    await tester.tap(find.widgetWithText(ChoiceChip, etiqueta));
    await tester.pumpAndSettle();
  }

  Future<void> tocarCargarMas(WidgetTester tester) async {
    final boton = find.widgetWithText(OutlinedButton, 'Cargar más');
    await tester.scrollUntilVisible(boton, 300, scrollable: find.byType(Scrollable).last);
    await tester.tap(boton);
    await tester.pumpAndSettle();
  }

  final tres = [_gasto(1, 'comida'), _gasto(2, 'transporte'), _gasto(3, 'comida')];

  testWidgets('los chips muestran «Todas» y cada categoría cargada, sin repetir', (tester) async {
    await entrar(tester, gastosA: tres);
    expect(chips(tester), ['Todas', 'comida', 'transporte']);
    expect(chipSeleccionado(tester), 'Todas');
    expect(titulosVisibles(tester), ['Gasto 1', 'Gasto 2', 'Gasto 3']);
  });

  testWidgets('elegir «comida» muestra solo sus gastos sin tocar la lista ni la caché', (tester) async {
    final g = await entrar(tester, gastosA: tres);
    final copiaAntes = List.of(Hive.box('gastos_1').get('gastos') as List);

    await tocarChip(tester, 'comida');
    expect(chipSeleccionado(tester), 'comida');
    expect(titulosVisibles(tester), ['Gasto 1', 'Gasto 3']);
    expect(g.gastos.map((x) => x.id).toList(), [1, 2, 3], reason: 'La lista cargada no cambia');
    expect(Hive.box('gastos_1').get('gastos'), copiaAntes, reason: 'La caché no cambia');
    expect(servidor.consultasDeListado, hasLength(1), reason: 'Filtrar no pide nada al servidor');
  });

  testWidgets('volver a «Todas» restablece la lista cargada', (tester) async {
    await entrar(tester, gastosA: tres);
    await tocarChip(tester, 'comida');
    await tocarChip(tester, 'Todas');
    expect(chipSeleccionado(tester), 'Todas');
    expect(titulosVisibles(tester), ['Gasto 1', 'Gasto 2', 'Gasto 3']);
  });

  testWidgets('con filtro, «Cargar más» pide skip=20&limit=20 y suma las coincidencias nuevas', (tester) async {
    // 45 gastos; «transporte» cada 10 (ids 10, 20 | 30, 40): el resto, comida.
    final cuarentaYCinco = List.generate(45, (i) => _gasto(i + 1, (i + 1) % 10 == 0 ? 'transporte' : 'comida'));
    final g = await entrar(tester, gastosA: cuarentaYCinco, paginar: true);
    await tocarChip(tester, 'transporte');
    expect(titulosVisibles(tester), ['Gasto 10', 'Gasto 20']);

    await tocarCargarMas(tester);
    expect(servidor.consultasDeListado, [
      {'skip': '0', 'limit': '20'},
      {'skip': '20', 'limit': '20'},
    ]);
    expect(g.gastos, hasLength(40), reason: 'La página se suma a la lista cargada, sin filtrar');
    expect(chipSeleccionado(tester), 'transporte');
    expect(titulosVisibles(tester), ['Gasto 10', 'Gasto 20', 'Gasto 30', 'Gasto 40']);
  });

  testWidgets('sin coincidencias y con páginas pendientes: se avisa, «Cargar más» sigue y trae las nuevas', (tester) async {
    // Página 1: un solo «otros» (id 5). Página 2: otro «otros» (id 25).
    final gastos = List.generate(45, (i) => _gasto(i + 1, {5, 25}.contains(i + 1) ? 'otros' : 'comida'));
    final g = await entrar(tester, gastosA: gastos, paginar: true);
    await tocarChip(tester, 'otros');
    expect(titulosVisibles(tester), ['Gasto 5']);

    // Se borra el último «otros» cargado: la selección se conserva.
    await tester.runAsync(() => g.eliminar(5));
    await tester.pumpAndSettle();
    expect(chipSeleccionado(tester), 'otros', reason: 'El chip sigue visible y seleccionado');
    expect(titulosVisibles(tester), isEmpty);
    expect(find.text('No hay gastos de otros entre los cargados.'), findsOneWidget);
    expect(find.text('Aún no registras gastos en este viaje'), findsNothing);
    expect(g.hayMas, isTrue);

    await tocarCargarMas(tester);
    expect(titulosVisibles(tester), ['Gasto 25']);
    expect(find.text('No hay gastos de otros entre los cargados.'), findsNothing);
  });

  testWidgets('recargar conserva la selección, también sobre la copia sin conexión', (tester) async {
    await entrar(tester, gastosA: tres);
    await tocarChip(tester, 'comida');

    servidor.sinRedAlListar = true;
    await tester.tap(find.byTooltip('Recargar'));
    await tester.pumpAndSettle();
    expect(find.byType(MaterialBanner), findsOneWidget, reason: 'Se ve la copia local');
    expect(chipSeleccionado(tester), 'comida');
    expect(titulosVisibles(tester), ['Gasto 1', 'Gasto 3']);

    servidor.sinRedAlListar = false;
    await tester.tap(find.byTooltip('Recargar'));
    await tester.pumpAndSettle();
    expect(find.byType(MaterialBanner), findsNothing);
    expect(chipSeleccionado(tester), 'comida');
    expect(titulosVisibles(tester), ['Gasto 1', 'Gasto 3']);
  });

  testWidgets('al cambiar de sesión el filtro vuelve a «Todas»: B no hereda el de A', (tester) async {
    final g = await entrar(tester, gastosA: tres, gastosB: [_gasto(50, 'transporte'), _gasto(51, 'otros')]);
    await tocarChip(tester, 'comida');
    expect(g.categoriaFiltro.value, 'comida');

    await tester.runAsync(auth.cerrarSesion);
    await tester.pumpAndSettle();
    expect(g.categoriaFiltro.value, isNull);

    await tester.runAsync(() async {
      await auth.iniciarSesion(_correoB, _clave);
      await g.cargaInicial;
    });
    await tester.pumpAndSettle();
    expect(chipSeleccionado(tester), 'Todas');
    expect(chips(tester), ['Todas', 'transporte', 'otros']);
    expect(titulosVisibles(tester), ['Gasto 50', 'Gasto 51']);
  });

  testWidgets('«Aún no registras gastos» solo cuando no hay gastos ni páginas pendientes', (tester) async {
    await entrar(tester, gastosA: const []);
    expect(find.byType(EmptyView), findsOneWidget);
    expect(find.text('Aún no registras gastos en este viaje'), findsOneWidget);
    expect(find.byType(ChoiceChip), findsNothing);
  });

  testWidgets('con páginas pendientes, una página vacía no se presenta como «sin gastos»', (tester) async {
    // El servidor informa 45 en total, pero la primera página llega vacía.
    final g = await entrar(tester, gastosA: const [], totalA: 45);
    expect(g.hayMas, isTrue);
    expect(find.text('Aún no registras gastos en este viaje'), findsNothing);
    expect(find.widgetWithText(OutlinedButton, 'Cargar más'), findsOneWidget);
  });

  testWidgets('regresión: lista cargada vacía con filtro y páginas pendientes — el filtro se ve y se quita', (tester) async {
    // La página 1 trae un «otros»; luego el servidor queda sin gastos en la
    // primera página pero sigue informando 45 en total.
    final g = await entrar(tester, gastosA: [_gasto(5, 'otros')], totalA: 45);
    await tocarChip(tester, 'otros');
    servidor.usuarios[_correoA]!.gastos = [];
    await tester.tap(find.byTooltip('Recargar'));
    await tester.pumpAndSettle();
    expect(g.gastos, isEmpty);
    expect(g.hayMas, isTrue);

    // El filtro activo sigue visible, junto con «Todas» y «Cargar más».
    expect(chips(tester), ['Todas', 'otros']);
    expect(chipSeleccionado(tester), 'otros');
    expect(find.widgetWithText(OutlinedButton, 'Cargar más'), findsOneWidget);
    expect(find.text('Aún no registras gastos en este viaje'), findsNothing);

    await tocarChip(tester, 'Todas');
    expect(g.categoriaFiltro.value, isNull);
    expect(chipSeleccionado(tester), 'Todas');

    // La siguiente carga muestra sus gastos sin el filtro anterior.
    servidor.usuarios[_correoA]!.gastos = [_gasto(7, 'comida'), _gasto(8, 'comida')];
    await tocarCargarMas(tester);
    expect(titulosVisibles(tester), ['Gasto 7', 'Gasto 8']);
    expect(chipSeleccionado(tester), 'Todas');
  });

  testWidgets('en inglés: «All» y el aviso de sin coincidencias traducido', (tester) async {
    final g = await entrar(tester, gastosA: tres, idioma: const Locale('en', 'US'));
    expect(chips(tester).first, 'All');
    g.filtrar('otros'); // ninguno cargado
    await tester.pumpAndSettle();
    expect(chipSeleccionado(tester), 'otros');
    expect(find.text('No loaded expenses in otros.'), findsOneWidget);
  });
}
