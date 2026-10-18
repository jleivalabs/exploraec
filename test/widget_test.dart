import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:exploraec/bienvenida_claude_design.dart';
import 'package:exploraec/controllers/places_controller.dart';
import 'package:exploraec/main.dart';
import 'package:exploraec/models/place.dart';
import 'package:exploraec/screens/add_place_screen.dart';
import 'package:exploraec/screens/detail_screen.dart';
import 'package:exploraec/screens/favorites_placeholder_screen.dart';
import 'package:exploraec/screens/home_screen.dart';
import 'package:exploraec/screens/map_placeholder_screen.dart';
import 'package:exploraec/theme/app_theme.dart';
import 'package:exploraec/widgets/empty_view.dart';
import 'package:exploraec/widgets/error_view.dart';
import 'package:exploraec/widgets/loading_view.dart';
import 'package:exploraec/widgets/place_card.dart';

const _subtitulo = 'Descubre y guarda lugares cerca de ti';
const _mensaje = 'Próximamente exploraremos lugares';

// fetchLugaresSimulado espera 1 s con Future.delayed. En los tests el reloj
// es simulado: hay que avanzarlo a mano. No se usa pumpAndSettle mientras
// carga, porque el CircularProgressIndicator anima sin fin.
const _demoraCarga = Duration(seconds: 1);
const _mensajeCarga = 'Buscando lugares cercanos...';
const _mensajeError = 'No se pudo conectar con el servidor (simulado)';
const _mensajeVacio = 'Todavía no hay lugares guardados';

/// Comprueba que Inicio está cargando y avanza el reloj hasta terminar.
Future<void> _esperarCarga(WidgetTester tester) async {
  expect(find.byType(LoadingView), findsOneWidget);
  expect(find.text(_mensajeCarga), findsOneWidget);
  await tester.pump(_demoraCarga);
  await tester.pumpAndSettle();
  expect(find.byType(LoadingView), findsNothing);
}

// Avisos de GetX (Get.snackbar): duran 3 s y luego animan su salida.
const _duracionAviso = Duration(seconds: 3);

/// Espera a que el aviso visible termine y se cierre. Necesario porque la
/// cola de avisos de GetX es estática: Get.reset() no la vacía, y un aviso
/// abierto que pase a la prueba siguiente hace que Get.back() cierre ese
/// aviso en vez de la pantalla.
Future<void> _esperarCierreDeAviso(WidgetTester tester) async {
  await tester.pump(_duracionAviso);
  await tester.pumpAndSettle();
  expect(Get.isSnackbarOpen, isFalse,
      reason: 'Quedó otro aviso abierto o en cola');
}

/// El mensaje de error dentro de ErrorView (el aviso también lo muestra).
Finder _mensajeEnErrorView() => find.descendant(
      of: find.byType(ErrorView),
      matching: find.textContaining(_mensajeError),
    );

/// El PlacesController que registró PlacesBinding al montar la app.
PlacesController _controller() => Get.find<PlacesController>();

/// Monta la app y espera a que Inicio termine la primera carga.
Future<void> _abrirAppCargada(WidgetTester tester) async {
  await tester.pumpWidget(const ExploraEcApp());
  await _esperarCarga(tester);
}

/// Elige una opción del menú "Simular estado" e inicia la recarga.
Future<void> _simular(WidgetTester tester, String opcion) async {
  await tester.tap(find.byTooltip('Simular estado (solo práctica)'));
  await tester.pumpAndSettle();
  await tester.tap(find.text(opcion));
  await tester.pump();
}

/// Fija el tamaño lógico de la pantalla de prueba (devicePixelRatio 1).
void _fijarTamano(WidgetTester tester, double ancho, {double alto = 800}) {
  tester.view.physicalSize = Size(ancho, alto);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

/// Columnas de la grilla de Inicio, o 1 si se muestra la lista.
int _columnasInicio(WidgetTester tester) {
  if (find.byType(ListView).evaluate().isNotEmpty) return 1;
  final grid = tester.widget<GridView>(find.byType(GridView));
  return (grid.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount)
      .crossAxisCount;
}

/// Simula la preferencia de tema del sistema y la restaura al terminar.
void _simularBrillo(WidgetTester tester, Brightness brillo) {
  tester.platformDispatcher.platformBrightnessTestValue = brillo;
  addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
}

/// Tema efectivo que recibe un widget ya montado.
ThemeData _temaDe(WidgetTester tester, Finder finder) =>
    Theme.of(tester.element(finder));

Future<void> _tocarEmpezarYVerSnackBar(WidgetTester tester) async {
  expect(find.widgetWithText(FilledButton, 'Empezar'), findsOneWidget);
  expect(find.text(_mensaje), findsNothing);

  await tester.tap(find.text('Empezar'));
  await tester.pump();

  expect(find.byType(SnackBar), findsOneWidget);
  expect(find.text(_mensaje), findsOneWidget);
}

void main() {
  setUpAll(() {
    // Evita descargar fuentes por internet durante las pruebas;
    // se usa la fuente de respaldo del entorno de test.
    GoogleFonts.config.allowRuntimeFetching = false;
    // Silencia los registros [GETX] en la salida de las pruebas.
    Get.isLogEnable = false;
  });

  // Dos estados globales que sobreviven entre pruebas y se limpian tras
  // cada una:
  // - lugaresEjemplo, la lista en memoria (agregar lugares la modifica);
  // - el registro de GetX: sin Get.reset() la siguiente prueba recibiría
  //   el PlacesController anterior, ya cargado y con sus modos simulados.
  final lugaresOriginales = List<Place>.of(lugaresEjemplo);
  tearDown(() {
    Get.reset();
    // El idioma y el diccionario de GetX también son estáticos y Get.reset()
    // no los toca: se dejan como antes de la prueba.
    Get.locale = null;
    Get.fallbackLocale = null;
    Get.clearTranslations();
    lugaresEjemplo
      ..clear()
      ..addAll(lugaresOriginales);
  });

  testWidgets('ExploraEcApp muestra HomeScreen con tarjetas de lugares', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const ExploraEcApp());

    expect(find.byType(HomeScreen), findsOneWidget);
    expect(find.text('Cargando lugares...'), findsNothing);
    expect(find.byType(PlaceCard), findsNothing);
    await _esperarCarga(tester);

    // ListView.builder solo construye lo visible: hay al menos una tarjeta
    // y la primera muestra los datos del primer lugar.
    expect(find.byType(PlaceCard), findsWidgets);
    final primero = lugaresEjemplo.first;
    expect(find.text(primero.nombre), findsOneWidget);
    expect(find.text(primero.descripcion), findsOneWidget);

    // El último lugar puede quedar fuera de pantalla: se desplaza hasta él.
    final ultimo = lugaresEjemplo.last;
    await tester.scrollUntilVisible(
      find.text(ultimo.nombre),
      200,
      scrollable: find.byType(Scrollable),
    );
    expect(find.text(ultimo.nombre), findsOneWidget);
  });

  testWidgets('Tocar una tarjeta abre el detalle de ese lugar y se vuelve a Inicio', (
    WidgetTester tester,
  ) async {
    await _abrirAppCargada(tester);

    Future<void> abrirYVerificar(Place lugar, Place otro) async {
      final tarjeta = find.widgetWithText(PlaceCard, lugar.nombre);
      await tester.scrollUntilVisible(
        tarjeta,
        200,
        scrollable: find.byType(Scrollable),
      );
      await tester.tap(tarjeta);
      await tester.pumpAndSettle();

      // El detalle recibió el Place correcto por su constructor.
      final detalle = find.byType(DetailScreen);
      expect(detalle, findsOneWidget);
      expect(tester.widget<DetailScreen>(detalle).place, same(lugar));
      Finder enDetalle(String texto) =>
          find.descendant(of: detalle, matching: find.text(texto));
      expect(enDetalle(lugar.nombre), findsNWidgets(2)); // AppBar + título
      expect(enDetalle(lugar.categoria), findsOneWidget);
      expect(enDetalle(lugar.descripcion), findsOneWidget);
      expect(enDetalle(otro.nombre), findsNothing);

      // Volver a Inicio con el botón atrás del AppBar (Navigator.pop).
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.byType(DetailScreen), findsNothing);
      expect(find.byType(HomeScreen), findsOneWidget);
    }

    final primero = lugaresEjemplo[0];
    final tercero = lugaresEjemplo[2];
    await abrirYVerificar(primero, tercero);
    await abrirYVerificar(tercero, primero);
  });

  testWidgets('La barra inferior recorre Inicio, Mapa, Favoritos e Inicio', (
    WidgetTester tester,
  ) async {
    await _abrirAppCargada(tester);

    // Solo pump(): así se puede comprobar el primer frame de cada pestaña
    // (por ejemplo, que Inicio no pase por el estado de carga al volver).
    Future<void> tocarPestana(String etiqueta) async {
      await tester.tap(
        find.descendant(
          of: find.byType(BottomNavigationBar),
          matching: find.text(etiqueta),
        ),
      );
      await tester.pump();
    }

    int indiceActual() =>
        tester.widget<BottomNavigationBar>(find.byType(BottomNavigationBar))
            .currentIndex;

    expect(find.byType(HomeScreen), findsOneWidget);
    expect(find.text(lugaresEjemplo.first.nombre), findsOneWidget);
    expect(indiceActual(), 0);

    await tocarPestana('Mapa');
    expect(find.byType(MapPlaceholderScreen), findsOneWidget);
    expect(find.byType(HomeScreen), findsNothing);
    expect(find.text('Próximamente: mapa real (Sesión 5)'), findsOneWidget);
    expect(indiceActual(), 1);

    await tocarPestana('Favoritos');
    expect(find.byType(FavoritesPlaceholderScreen), findsOneWidget);
    expect(find.byType(MapPlaceholderScreen), findsNothing);
    // Desde la Sesión 4 Favoritos lee el contador del controller compartido.
    expect(find.textContaining('Favoritos marcados: 0.'), findsOneWidget);
    expect(indiceActual(), 2);

    await tocarPestana('Inicio');
    expect(find.byType(HomeScreen), findsOneWidget);
    // El estado vive en PlacesController, no en HomeScreen: al volver no
    // hay una carga nueva, los datos ya están.
    expect(find.byType(LoadingView), findsNothing);
    expect(find.byType(FavoritesPlaceholderScreen), findsNothing);
    expect(find.text(lugaresEjemplo.first.nombre), findsOneWidget);
    expect(indiceActual(), 0);
  });

  testWidgets('Cambiar de pestaña conserva el controller y sus datos', (
    WidgetTester tester,
  ) async {
    await _abrirAppCargada(tester);
    final controller = _controller();

    // Se deja Inicio en un estado distinto al inicial: modo vacío.
    await _simular(tester, 'Simular: vacío');
    await _esperarCarga(tester);
    expect(find.byType(EmptyView), findsOneWidget);

    Future<void> tocarPestana(String etiqueta) async {
      await tester.tap(
        find.descendant(
          of: find.byType(BottomNavigationBar),
          matching: find.text(etiqueta),
        ),
      );
      await tester.pump();
    }

    await tocarPestana('Mapa');
    expect(find.byType(HomeScreen), findsNothing);
    await tocarPestana('Favoritos');
    expect(find.byType(HomeScreen), findsNothing);
    await tocarPestana('Inicio');

    // Misma instancia, mismo estado: sigue vacío y sin recargar.
    expect(identical(_controller(), controller), isTrue);
    expect(controller.estado.value, EstadoCarga.exito);
    expect(controller.lugares, isEmpty);
    expect(find.byType(LoadingView), findsNothing);
    expect(find.byType(EmptyView), findsOneWidget);

    // Y al volver al modo normal, la lista regresa.
    await _simular(tester, 'Simular: normal');
    await _esperarCarga(tester);
    expect(find.byType(PlaceCard), findsWidgets);
    expect(controller.lugares.length, lugaresEjemplo.length);
  });

  group('Estados de carga de Inicio', () {
    testWidgets('Muestra la carga hasta que pasa la demora simulada', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(const ExploraEcApp());
      expect(find.byType(LoadingView), findsOneWidget);
      expect(find.text(_mensajeCarga), findsOneWidget);

      // Justo antes de cumplirse el segundo sigue cargando.
      await tester.pump(_demoraCarga - const Duration(milliseconds: 1));
      expect(find.byType(LoadingView), findsOneWidget);
      expect(find.byType(PlaceCard), findsNothing);

      await tester.pump(const Duration(milliseconds: 1));
      await tester.pumpAndSettle();
      expect(find.byType(LoadingView), findsNothing);
      expect(find.byType(PlaceCard), findsWidgets);
    });

    testWidgets('Simular vacío muestra EmptyView sin tarjetas', (
      WidgetTester tester,
    ) async {
      await _abrirAppCargada(tester);

      await _simular(tester, 'Simular: vacío');
      await _esperarCarga(tester);

      expect(find.byType(EmptyView), findsOneWidget);
      expect(find.text(_mensajeVacio), findsOneWidget);
      expect(find.byType(PlaceCard), findsNothing);
    });

    testWidgets('Simular error muestra ErrorView y Reintentar mantiene el error', (
      WidgetTester tester,
    ) async {
      await _abrirAppCargada(tester);

      await _simular(tester, 'Simular: error');
      await _esperarCarga(tester);
      expect(find.byType(ErrorView), findsOneWidget);
      expect(_mensajeEnErrorView(), findsOneWidget);
      expect(find.byType(PlaceCard), findsNothing);

      await _esperarCierreDeAviso(tester);

      // El modo error sigue activo: reintentar vuelve a cargar y vuelve a fallar.
      await tester.tap(find.text('Reintentar'));
      await tester.pump();
      await _esperarCarga(tester);
      expect(find.byType(ErrorView), findsOneWidget);
      expect(_mensajeEnErrorView(), findsOneWidget);
      await _esperarCierreDeAviso(tester);
    });

    testWidgets('Tras un error, Simular normal recupera la lista', (
      WidgetTester tester,
    ) async {
      await _abrirAppCargada(tester);
      await _simular(tester, 'Simular: error');
      await _esperarCarga(tester);
      expect(find.byType(ErrorView), findsOneWidget);
      // El aviso de error se muestra arriba, sobre la AppBar: se espera a
      // que se cierre antes de abrir el menú.
      await _esperarCierreDeAviso(tester);

      await _simular(tester, 'Simular: normal');
      await _esperarCarga(tester);
      expect(find.byType(ErrorView), findsNothing);
      expect(find.byType(PlaceCard), findsWidgets);
      expect(find.text(lugaresEjemplo.first.nombre), findsOneWidget);
    });
  });

  group('Layout responsivo de Inicio', () {
    // Anchos alrededor de los dos cortes del bloque (600 y 900).
    final casos = <double, int>{599: 1, 600: 2, 899: 2, 900: 3};

    for (final caso in casos.entries) {
      testWidgets('Ancho ${caso.key.toInt()} muestra ${caso.value} columna(s)', (
        WidgetTester tester,
      ) async {
        _fijarTamano(tester, caso.key);
        await _abrirAppCargada(tester);

        expect(tester.takeException(), isNull); // sin desbordamientos
        expect(_columnasInicio(tester), caso.value);
        if (caso.value == 1) {
          expect(find.byType(ListView), findsOneWidget);
          expect(find.byType(GridView), findsNothing);
        } else {
          expect(find.byType(GridView), findsOneWidget);
          expect(find.byType(ListView), findsNothing);
        }
        expect(find.byType(PlaceCard), findsWidgets);
      });
    }

    testWidgets('Cambiar de ancho en vivo cambia el layout sin desbordar', (
      WidgetTester tester,
    ) async {
      _fijarTamano(tester, 599);
      await _abrirAppCargada(tester);

      for (final caso in casos.entries) {
        tester.view.physicalSize = Size(caso.key, 800);
        await tester.pump();
        expect(tester.takeException(), isNull,
            reason: 'Desbordamiento a ${caso.key} px');
        expect(_columnasInicio(tester), caso.value,
            reason: 'Columnas a ${caso.key} px');
      }
    });

    for (final ancho in [400.0, 700.0, 1000.0]) {
      testWidgets('A ${ancho.toInt()} px las tarjetas abren el detalle correcto', (
        WidgetTester tester,
      ) async {
        _fijarTamano(tester, ancho);
        await _abrirAppCargada(tester);

        // El último lugar: en la grilla queda en otra fila/columna.
        final lugar = lugaresEjemplo.last;
        final tarjeta = find.widgetWithText(PlaceCard, lugar.nombre);
        await tester.scrollUntilVisible(
          tarjeta,
          200,
          scrollable: find.byType(Scrollable),
        );
        // scrollUntilVisible se detiene cuando la tarjeta ya está construida,
        // que puede ser en la zona de caché, fuera de la pantalla:
        // ensureVisible la desplaza hasta que se vea y se pueda tocar.
        await tester.ensureVisible(tarjeta);
        await tester.pumpAndSettle();
        await tester.tap(tarjeta);
        await tester.pumpAndSettle();

        final detalle = find.byType(DetailScreen);
        expect(tester.widget<DetailScreen>(detalle).place, same(lugar));
        expect(
          find.descendant(of: detalle, matching: find.text(lugar.descripcion)),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('Accesibilidad de PlaceCard', () {
    const hint = 'Toca dos veces para ver el detalle';
    String etiqueta(Place p) => '${p.nombre}, categoría ${p.categoria}';

    testWidgets('Expone etiqueta, indicación y rol de botón', (
      WidgetTester tester,
    ) async {
      final semantics = tester.ensureSemantics();
      _fijarTamano(tester, 400);
      await _abrirAppCargada(tester);

      final lugar = lugaresEjemplo.first;
      final nodo = find.bySemanticsLabel(etiqueta(lugar));
      expect(nodo, findsOneWidget);
      expect(
        tester.getSemantics(nodo),
        isSemantics(
          label: etiqueta(lugar),
          hint: hint,
          isButton: true,
          hasTapAction: true,
        ),
      );
      semantics.dispose();
    });

    testWidgets('El contenido de la tarjeta no se anuncia duplicado', (
      WidgetTester tester,
    ) async {
      final semantics = tester.ensureSemantics();
      _fijarTamano(tester, 400);
      await _abrirAppCargada(tester);

      final lugar = lugaresEjemplo.first;
      // Los textos sueltos se ven en pantalla...
      expect(find.text(lugar.nombre), findsOneWidget);
      expect(find.text(lugar.descripcion), findsOneWidget);
      // ...pero en el árbol semántico solo existe la etiqueta combinada.
      expect(find.bySemanticsLabel(lugar.nombre), findsNothing);
      expect(find.bySemanticsLabel(lugar.descripcion), findsNothing);
      expect(find.bySemanticsLabel(lugar.categoria), findsNothing);
      expect(find.bySemanticsLabel(etiqueta(lugar)), findsOneWidget);

      // Ningún nodo hijo de la tarjeta repite su contenido. Desde la
      // Sesión 4 el único hijo es el botón de favorito (corazón), que se
      // anuncia por su tooltip, no por los textos de la tarjeta.
      final nodo = tester.getSemantics(find.bySemanticsLabel(etiqueta(lugar)));
      final hijos = <SemanticsData>[];
      nodo.visitChildren((hijo) {
        hijos.add(hijo.getSemanticsData());
        return true;
      });
      for (final hijo in hijos) {
        final anunciado = '${hijo.label} ${hijo.value} ${hijo.tooltip}';
        for (final texto in [lugar.nombre, lugar.categoria, lugar.descripcion]) {
          expect(anunciado.contains(texto), isFalse,
              reason: 'Un hijo de la tarjeta repite "$texto"');
        }
      }
      expect(hijos, hasLength(1));
      expect(hijos.single.tooltip, 'Agregar a favoritos');
      expect(hijos.single.flagsCollection.isButton, isTrue);
      semantics.dispose();
    });

    testWidgets('La acción semántica de toque abre el detalle correcto', (
      WidgetTester tester,
    ) async {
      final semantics = tester.ensureSemantics();
      _fijarTamano(tester, 400);
      await _abrirAppCargada(tester);

      final lugar = lugaresEjemplo[1];
      final nodo = tester.getSemantics(find.bySemanticsLabel(etiqueta(lugar)));
      expect(nodo.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);

      // Igual que un lector de pantalla: se ejecuta la acción sobre el nodo,
      // sin tocar coordenadas de la pantalla.
      nodo.owner!.performAction(nodo.id, SemanticsAction.tap);
      await tester.pumpAndSettle();

      final detalle = find.byType(DetailScreen);
      expect(detalle, findsOneWidget);
      expect(tester.widget<DetailScreen>(detalle).place, same(lugar));
      semantics.dispose();
    });
  });

  group('Modo oscuro según el sistema', () {
    testWidgets('Con preferencia clara usa AppTheme.theme', (
      WidgetTester tester,
    ) async {
      _simularBrillo(tester, Brightness.light);
      await _abrirAppCargada(tester);

      final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
      expect(app.themeMode, ThemeMode.system);
      final tema = _temaDe(tester, find.byType(HomeScreen));
      expect(tema.brightness, Brightness.light);
      expect(tema.colorScheme.primary, AppTheme.theme.colorScheme.primary);
      expect(tema.scaffoldBackgroundColor, AppTheme.theme.scaffoldBackgroundColor);
    });

    testWidgets('Con preferencia oscura usa AppTheme.darkTheme', (
      WidgetTester tester,
    ) async {
      _simularBrillo(tester, Brightness.dark);
      await _abrirAppCargada(tester);

      final tema = _temaDe(tester, find.byType(HomeScreen));
      expect(tema.brightness, Brightness.dark);
      expect(tema.colorScheme.primary, AppTheme.darkTheme.colorScheme.primary);
      expect(tema.colorScheme.surface, AppTheme.darkTheme.colorScheme.surface);
      expect(find.byType(PlaceCard), findsWidgets);
    });

    testWidgets('Cambiar la preferencia en vivo cambia el tema', (
      WidgetTester tester,
    ) async {
      _simularBrillo(tester, Brightness.light);
      await _abrirAppCargada(tester);
      expect(_temaDe(tester, find.byType(HomeScreen)).brightness, Brightness.light);

      tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
      await tester.pumpAndSettle(); // transición animada entre temas
      expect(_temaDe(tester, find.byType(HomeScreen)).brightness, Brightness.dark);
    });

    testWidgets('En modo oscuro Inicio muestra normal, vacío y error', (
      WidgetTester tester,
    ) async {
      _simularBrillo(tester, Brightness.dark);
      await _abrirAppCargada(tester);

      // Normal
      expect(find.byType(PlaceCard), findsWidgets);
      expect(_temaDe(tester, find.byType(PlaceCard).first).brightness,
          Brightness.dark);
      expect(tester.takeException(), isNull);

      // Vacío
      await _simular(tester, 'Simular: vacío');
      await _esperarCarga(tester);
      expect(find.byType(EmptyView), findsOneWidget);
      expect(find.text(_mensajeVacio), findsOneWidget);
      expect(_temaDe(tester, find.byType(EmptyView)).brightness, Brightness.dark);
      expect(tester.takeException(), isNull);

      // Error
      await _simular(tester, 'Simular: error');
      await _esperarCarga(tester);
      expect(find.byType(ErrorView), findsOneWidget);
      expect(_mensajeEnErrorView(), findsOneWidget);
      expect(find.text('Reintentar'), findsOneWidget);
      expect(_temaDe(tester, find.byType(ErrorView)).brightness, Brightness.dark);
      expect(tester.takeException(), isNull);
      await _esperarCierreDeAviso(tester);
    });
  });

  group('Favoritos en memoria (Paso 6A)', () {
    const tooltipAgregar = 'Agregar a favoritos';
    const tooltipQuitar = 'Quitar de favoritos';

    Finder tarjetaDe(Place lugar) => find.widgetWithText(PlaceCard, lugar.nombre);
    Finder corazonDe(Place lugar) => find.descendant(
          of: tarjetaDe(lugar),
          matching: find.byType(IconButton),
        );
    IconButton botonCorazon(WidgetTester tester, Place lugar) =>
        tester.widget<IconButton>(corazonDe(lugar));
    IconData? iconoCorazon(WidgetTester tester, Place lugar) =>
        (botonCorazon(tester, lugar).icon as Icon).icon;

    Future<void> tocarCorazon(WidgetTester tester, Place lugar) async {
      await tester.tap(corazonDe(lugar));
      await tester.pump();
    }

    Future<void> tocarPestana(WidgetTester tester, String etiqueta) async {
      await tester.tap(find.descendant(
        of: find.byType(BottomNavigationBar),
        matching: find.text(etiqueta),
      ));
      await tester.pump();
    }

    testWidgets('Inicio y Favoritos usan la misma instancia del controller', (
      WidgetTester tester,
    ) async {
      await _abrirAppCargada(tester);
      final controller = _controller();
      expect(
        identical(tester.widget<HomeScreen>(find.byType(HomeScreen)).controller,
            controller),
        isTrue,
      );

      // Lo que se marca desde Inicio se ve en el contador de Favoritos.
      await tocarCorazon(tester, lugaresEjemplo.first);
      await tocarPestana(tester, 'Favoritos');
      expect(identical(_controller(), controller), isTrue);
      expect(find.textContaining('Favoritos marcados: 1.'), findsOneWidget);
    });

    testWidgets('El corazón marca y desmarca sin abrir el detalle', (
      WidgetTester tester,
    ) async {
      await _abrirAppCargada(tester);
      final controller = _controller();
      final lugar = lugaresEjemplo.first;

      expect(controller.esFavorito(lugar), isFalse);
      expect(iconoCorazon(tester, lugar), Icons.favorite_border);
      expect(botonCorazon(tester, lugar).tooltip, tooltipAgregar);

      await tocarCorazon(tester, lugar);
      await tester.pumpAndSettle();
      expect(find.byType(DetailScreen), findsNothing);
      expect(controller.esFavorito(lugar), isTrue);
      expect(iconoCorazon(tester, lugar), Icons.favorite);
      expect(botonCorazon(tester, lugar).tooltip, tooltipQuitar);

      await tocarCorazon(tester, lugar);
      await tester.pumpAndSettle();
      expect(find.byType(DetailScreen), findsNothing);
      expect(controller.esFavorito(lugar), isFalse);
      expect(iconoCorazon(tester, lugar), Icons.favorite_border);
      expect(botonCorazon(tester, lugar).tooltip, tooltipAgregar);

      // Tocar el resto de la tarjeta sigue abriendo el detalle.
      await tester.tap(find.descendant(
          of: tarjetaDe(lugar), matching: find.text(lugar.descripcion)));
      await tester.pumpAndSettle();
      expect(tester.widget<DetailScreen>(find.byType(DetailScreen)).place,
          same(lugar));
    });

    testWidgets('No se añaden favoritos duplicados', (
      WidgetTester tester,
    ) async {
      await _abrirAppCargada(tester);
      final controller = _controller();
      final lugar = lugaresEjemplo.first;

      await tocarCorazon(tester, lugar);
      expect(controller.favoritos.where((p) => p.id == lugar.id).length, 1);

      // Otra instancia con el mismo id cuenta como el mismo lugar: alterna
      // (lo quita) en vez de sumar un duplicado.
      final copia = Place(
        id: lugar.id,
        nombre: lugar.nombre,
        categoria: lugar.categoria,
        descripcion: lugar.descripcion,
        lat: lugar.lat,
        lng: lugar.lng,
      );
      expect(controller.esFavorito(copia), isTrue);
      controller.alternarFavorito(copia);
      await tester.pump();
      expect(controller.favoritos, isEmpty);
      expect(iconoCorazon(tester, lugar), Icons.favorite_border);

      // Marcar dos lugares distintos deja dos favoritos con ids únicos.
      final otro = lugaresEjemplo[1];
      await tocarCorazon(tester, lugar);
      await tocarCorazon(tester, otro);
      final ids = controller.favoritos.map((p) => p.id).toList();
      expect(ids, hasLength(2));
      expect(ids.toSet(), hasLength(2));
    });

    testWidgets('totalFavoritos y el contador de la pestaña se actualizan', (
      WidgetTester tester,
    ) async {
      await _abrirAppCargada(tester);
      final controller = _controller();
      expect(controller.totalFavoritos, 0);

      await tocarPestana(tester, 'Favoritos');
      expect(find.textContaining('Favoritos marcados: 0.'), findsOneWidget);
      await tocarPestana(tester, 'Inicio');

      await tocarCorazon(tester, lugaresEjemplo[0]);
      await tocarCorazon(tester, lugaresEjemplo[1]);
      expect(controller.totalFavoritos, 2);
      await tocarPestana(tester, 'Favoritos');
      expect(find.textContaining('Favoritos marcados: 2.'), findsOneWidget);

      // Con la pestaña Favoritos visible, el contador reacciona al instante.
      controller.alternarFavorito(lugaresEjemplo[0]);
      await tester.pump();
      expect(controller.totalFavoritos, 1);
      expect(find.textContaining('Favoritos marcados: 1.'), findsOneWidget);
    });

    testWidgets('Las marcas se conservan al cambiar de pestaña', (
      WidgetTester tester,
    ) async {
      await _abrirAppCargada(tester);
      final marcado = lugaresEjemplo[0];
      final sinMarcar = lugaresEjemplo[1];
      await tocarCorazon(tester, marcado);

      await tocarPestana(tester, 'Mapa');
      expect(find.byType(HomeScreen), findsNothing);
      await tocarPestana(tester, 'Favoritos');
      await tocarPestana(tester, 'Inicio');
      // Inicio se reconstruye sin recargar y con las mismas marcas.
      expect(find.byType(LoadingView), findsNothing);
      expect(iconoCorazon(tester, marcado), Icons.favorite);
      expect(botonCorazon(tester, marcado).tooltip, tooltipQuitar);
      expect(iconoCorazon(tester, sinMarcar), Icons.favorite_border);
      expect(botonCorazon(tester, sinMarcar).tooltip, tooltipAgregar);
      expect(_controller().totalFavoritos, 1);
    });
  });

  group('Idioma con GetX (Paso 6B)', () {
    const textosEs = {
      'barra': ['Inicio', 'Mapa', 'Favoritos'],
      'menu': ['Simular: normal', 'Simular: vacío', 'Simular: error'],
      'tooltip': ['Cambiar idioma'],
    };
    const textosEn = {
      'barra': ['Home', 'Map', 'Favorites'],
      'menu': ['Simulate: normal', 'Simulate: empty', 'Simulate: error'],
      'tooltip': ['Change language'],
    };
    const claves = [
      'inicio', 'mapa', 'favoritos', 'idioma',
      'sim_normal', 'sim_vacio', 'sim_error',
    ];

    Finder enBarra(String texto) => find.descendant(
          of: find.byType(BottomNavigationBar),
          matching: find.text(texto),
        );

    // Get.updateLocale() reconstruye toda la app con
    // engine.performReassemble(). En el reloj simulado de las pruebas, ese
    // frame de arranque choca con el pump siguiente ("schedulerPhase ==
    // SchedulerPhase.idle"). Dentro de runAsync el reensamblado termina
    // fuera de cualquier frame; después se dibuja con pumpAndSettle.
    Future<void> tocarIdioma(WidgetTester tester, String tooltip) async {
      await tester.runAsync(() async {
        await tester.tap(find.byTooltip(tooltip));
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pumpAndSettle();
    }

    Future<void> abrirMenu(WidgetTester tester) async {
      await tester.tap(find.byTooltip('Simular estado (solo práctica)'));
      await tester.pumpAndSettle();
    }

    Future<void> cerrarMenu(WidgetTester tester) async {
      await tester.tapAt(Offset.zero); // toque fuera del menú
      await tester.pumpAndSettle();
    }

    /// Comprueba barra, menú y tooltip en un idioma, y que no se vea
    /// ninguna clave sin traducir.
    Future<void> comprobarTextos(
      WidgetTester tester,
      Map<String, List<String>> esperados,
      Map<String, List<String>> otroIdioma,
    ) async {
      for (final texto in esperados['barra']!) {
        expect(enBarra(texto), findsOneWidget, reason: texto);
      }
      for (final texto in otroIdioma['barra']!) {
        expect(enBarra(texto), findsNothing, reason: texto);
      }
      expect(find.byTooltip(esperados['tooltip']!.single), findsOneWidget);

      await abrirMenu(tester);
      for (final texto in esperados['menu']!) {
        expect(find.text(texto), findsOneWidget, reason: texto);
      }
      for (final texto in otroIdioma['menu']!) {
        expect(find.text(texto), findsNothing, reason: texto);
      }
      for (final clave in claves) {
        expect(find.text(clave), findsNothing, reason: 'Clave sin resolver: $clave');
        expect(find.byTooltip(clave), findsNothing, reason: 'Clave sin resolver: $clave');
      }
      await cerrarMenu(tester);
    }

    testWidgets('Inicio arranca en español', (WidgetTester tester) async {
      await _abrirAppCargada(tester);
      expect(Get.locale, const Locale('es', 'EC'));
      await comprobarTextos(tester, textosEs, textosEn);
    });

    testWidgets('El botón cambia a inglés y vuelve a español', (
      WidgetTester tester,
    ) async {
      await _abrirAppCargada(tester);

      await tocarIdioma(tester, 'Cambiar idioma');
      expect(Get.locale, const Locale('en', 'US'));
      await comprobarTextos(tester, textosEn, textosEs);

      // Las opciones traducidas siguen funcionando.
      await abrirMenu(tester);
      await tester.tap(find.text('Simulate: empty'));
      await tester.pump();
      await _esperarCarga(tester);
      expect(find.byType(EmptyView), findsOneWidget);

      await tocarIdioma(tester, 'Change language');
      expect(Get.locale, const Locale('es', 'EC'));
      await comprobarTextos(tester, textosEs, textosEn);
    });

    testWidgets('Cambiar de idioma conserva controller, lugares y favoritos', (
      WidgetTester tester,
    ) async {
      await _abrirAppCargada(tester);
      final controller = _controller();
      final idsLugares = controller.lugares.map((p) => p.id).toList();
      final favorito = lugaresEjemplo[1];
      await tester.tap(find.descendant(
        of: find.widgetWithText(PlaceCard, favorito.nombre),
        matching: find.byType(IconButton),
      ));
      await tester.pump();
      expect(controller.esFavorito(favorito), isTrue);

      await tocarIdioma(tester, 'Cambiar idioma');

      // Misma instancia y mismos datos, sin volver a cargar.
      expect(identical(_controller(), controller), isTrue);
      expect(find.byType(LoadingView), findsNothing);
      expect(controller.estado.value, EstadoCarga.exito);
      expect(controller.lugares.map((p) => p.id).toList(), idsLugares);
      expect(find.byType(PlaceCard), findsWidgets);
      expect(controller.totalFavoritos, 1);
      expect(controller.esFavorito(favorito), isTrue);
      expect(
        tester
            .widget<IconButton>(find.descendant(
              of: find.widgetWithText(PlaceCard, favorito.nombre),
              matching: find.byType(IconButton),
            ))
            .tooltip,
        'Quitar de favoritos',
      );

      // En inglés, la pestaña Favoritos lee el mismo contador.
      await tester.tap(enBarra('Favorites'));
      await tester.pump();
      expect(find.textContaining('Favoritos marcados: 1.'), findsOneWidget);
      expect(
        tester.widget<BottomNavigationBar>(find.byType(BottomNavigationBar))
            .currentIndex,
        2,
      );

      // De vuelta en Inicio y otra vez en español: todo sigue igual.
      await tester.tap(enBarra('Home'));
      await tester.pump();
      await tocarIdioma(tester, 'Change language');
      expect(Get.locale, const Locale('es', 'EC'));
      expect(identical(_controller(), controller), isTrue);
      expect(find.byType(LoadingView), findsNothing);
      expect(controller.lugares.map((p) => p.id).toList(), idsLugares);
      expect(controller.esFavorito(favorito), isTrue);
    });
  });

  group('Contador y avisos de PlacesController', () {
    Future<void> agregarLugarDesdeFormulario(
      WidgetTester tester,
      String nombre, {
      bool? avisoAbiertoAlGuardar,
    }) async {
      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();
      await tester.enterText(
          find.widgetWithText(TextFormField, 'Nombre del lugar'), nombre);
      await tester.enterText(
          find.widgetWithText(TextFormField, 'Categoría'), 'Pruebas');
      await tester.enterText(find.widgetWithText(TextFormField, 'Descripción'),
          'Lugar sintético creado por la prueba.');
      if (avisoAbiertoAlGuardar != null) {
        // Precondición del escenario: sin esto la prueba no reproduce nada.
        expect(Get.isSnackbarOpen, avisoAbiertoAlGuardar,
            reason: 'Estado del aviso justo antes de pulsar Guardar');
      }
      await tester.tap(find.widgetWithText(ElevatedButton, 'Guardar'));
      await tester.pump();
      await tester.pumpAndSettle(); // transición de vuelta y entrada del aviso
    }

    testWidgets('El título muestra el total y sube al guardar', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(const ExploraEcApp());
      // Mientras carga, la lista aún está vacía.
      expect(find.text('ExploraEC (0)'), findsOneWidget);
      await _esperarCarga(tester);

      final total = lugaresEjemplo.length;
      expect(_controller().total, total);
      expect(find.text('ExploraEC ($total)'), findsOneWidget);

      await agregarLugarDesdeFormulario(tester, 'Mirador del Contador');
      expect(_controller().total, total + 1);
      expect(find.text('ExploraEC (${total + 1})'), findsOneWidget);
      expect(find.text('ExploraEC ($total)'), findsNothing);
      await _esperarCierreDeAviso(tester);

      // Vacío también se refleja en el contador.
      await _simular(tester, 'Simular: vacío');
      await _esperarCarga(tester);
      expect(find.text('ExploraEC (0)'), findsOneWidget);
    });

    testWidgets('Guardar un lugar muestra el aviso de alta', (
      WidgetTester tester,
    ) async {
      await _abrirAppCargada(tester);
      expect(Get.isSnackbarOpen, isFalse);

      await agregarLugarDesdeFormulario(tester, 'Mirador del Aviso');
      expect(find.byType(AddPlaceScreen), findsNothing);
      expect(Get.isSnackbarOpen, isTrue);
      expect(find.text('Lugar agregado'), findsOneWidget);
      expect(find.text('Ya aparece en Inicio'), findsOneWidget);

      await _esperarCierreDeAviso(tester);
      expect(find.text('Lugar agregado'), findsNothing);
    });

    testWidgets('Un error de carga muestra el aviso con el mensaje', (
      WidgetTester tester,
    ) async {
      await _abrirAppCargada(tester);
      // Una carga exitosa no avisa.
      expect(Get.isSnackbarOpen, isFalse);

      await _simular(tester, 'Simular: error');
      await _esperarCarga(tester);
      expect(Get.isSnackbarOpen, isTrue);
      expect(find.text('Error'), findsOneWidget);
      // El mensaje aparece en ErrorView y en el aviso.
      expect(find.textContaining(_mensajeError), findsNWidgets(2));
      expect(_mensajeEnErrorView(), findsOneWidget);

      await _esperarCierreDeAviso(tester);
      expect(find.text('Error'), findsNothing);
    });

    testWidgets('Recargar no registra workers adicionales', (
      WidgetTester tester,
    ) async {
      await _abrirAppCargada(tester);

      // Varias recargas exitosas: no avisan y no suman workers.
      for (var i = 0; i < 3; i++) {
        await _simular(tester, 'Simular: normal');
        await _esperarCarga(tester);
        expect(Get.isSnackbarOpen, isFalse);
      }

      // Cada error produce exactamente UN aviso. Si cada carga registrara
      // un worker, habría varios avisos en cola y, al cerrarse el primero,
      // se abriría otro (lo detecta _esperarCierreDeAviso).
      await _simular(tester, 'Simular: error');
      await _esperarCarga(tester);
      expect(find.text('Error'), findsOneWidget);
      await _esperarCierreDeAviso(tester);

      for (var i = 0; i < 3; i++) {
        await tester.tap(find.text('Reintentar'));
        await tester.pump();
        await _esperarCarga(tester);
        expect(find.text('Error'), findsOneWidget, reason: 'Reintento ${i + 1}');
        await _esperarCierreDeAviso(tester);
      }
    });

    int vecesEnController(String nombre) =>
        _controller().lugares.where((p) => p.nombre == nombre).length;
    int vecesEnDatos(String nombre) =>
        lugaresEjemplo.where((p) => p.nombre == nombre).length;

    testWidgets('Dos altas seguidas con el primer aviso visible cierran ambos formularios', (
      WidgetTester tester,
    ) async {
      await _abrirAppCargada(tester);
      final total = _controller().total;

      await agregarLugarDesdeFormulario(tester, 'Primer Lugar Rápido',
          avisoAbiertoAlGuardar: false);
      expect(find.byType(AddPlaceScreen), findsNothing);
      expect(find.text('Lugar agregado'), findsOneWidget);

      // Sin esperar a que el aviso desaparezca: es justo el caso del fallo.
      await agregarLugarDesdeFormulario(tester, 'Segundo Lugar Rápido',
          avisoAbiertoAlGuardar: true);
      expect(find.byType(AddPlaceScreen), findsNothing,
          reason: 'El segundo formulario debe cerrarse aunque hubiera un aviso');
      expect(find.byType(HomeScreen), findsOneWidget);

      expect(_controller().total, total + 2);
      expect(find.text('ExploraEC (${total + 2})'), findsOneWidget);
      for (final nombre in ['Primer Lugar Rápido', 'Segundo Lugar Rápido']) {
        expect(vecesEnController(nombre), 1, reason: nombre);
        expect(vecesEnDatos(nombre), 1, reason: nombre);
      }

      // El aviso de alta del segundo lugar se muestra tras cerrar el formulario.
      expect(Get.isSnackbarOpen, isTrue);
      expect(find.text('Lugar agregado'), findsOneWidget);
      await _esperarCierreDeAviso(tester);

      // Cada lugar aparece una sola vez en la lista de Inicio.
      for (final nombre in ['Primer Lugar Rápido', 'Segundo Lugar Rápido']) {
        final tarjeta = find.widgetWithText(PlaceCard, nombre);
        await tester.scrollUntilVisible(tarjeta, 200,
            scrollable: find.byType(Scrollable));
        expect(tarjeta, findsOneWidget, reason: nombre);
      }
    });

    testWidgets('Guardar con un aviso de error visible cierra el formulario', (
      WidgetTester tester,
    ) async {
      await _abrirAppCargada(tester);
      await _simular(tester, 'Simular: error');
      await _esperarCarga(tester);
      expect(find.text('Error'), findsOneWidget);
      final total = _controller().total;

      const nombre = 'Lugar Durante el Error';
      await agregarLugarDesdeFormulario(tester, nombre,
          avisoAbiertoAlGuardar: true);

      expect(find.byType(AddPlaceScreen), findsNothing);
      expect(find.byType(HomeScreen), findsOneWidget);
      expect(_controller().total, total + 1);
      expect(vecesEnController(nombre), 1);
      expect(vecesEnDatos(nombre), 1);
      // El aviso de error se cerró; ahora se muestra el de alta.
      expect(find.text('Error'), findsNothing);
      expect(find.text('Lugar agregado'), findsOneWidget);
      await _esperarCierreDeAviso(tester);
    });

    for (final brillo in Brightness.values) {
      testWidgets('Los avisos usan colores opacos del tema (${brillo.name})', (
        WidgetTester tester,
      ) async {
        _simularBrillo(tester, brillo);
        await _abrirAppCargada(tester);
        final esquema = _temaDe(tester, find.byType(HomeScreen)).colorScheme;
        expect(esquema.brightness, brillo);

        Color? colorDe(String texto) =>
            tester.widget<Text>(find.text(texto)).style?.color;

        await agregarLugarDesdeFormulario(tester, 'Lugar de Colores ${brillo.name}');
        final alta = tester.widget<GetSnackBar>(find.byType(GetSnackBar));
        expect(alta.backgroundColor, esquema.inverseSurface);
        expect(alta.backgroundColor.a, 1.0); // opaco
        expect(colorDe('Lugar agregado'), esquema.onInverseSurface);
        expect(colorDe('Ya aparece en Inicio'), esquema.onInverseSurface);
        await _esperarCierreDeAviso(tester);

        await _simular(tester, 'Simular: error');
        await _esperarCarga(tester);
        final error = tester.widget<GetSnackBar>(find.byType(GetSnackBar));
        expect(error.backgroundColor, esquema.error);
        expect(error.backgroundColor.a, 1.0);
        expect(colorDe('Error'), esquema.onError);
        await _esperarCierreDeAviso(tester);
      });
    }

    testWidgets('onClose() cancela el worker de errores', (
      WidgetTester tester,
    ) async {
      // App mínima de GetX: permite mostrar avisos sin montar Inicio.
      await tester.pumpWidget(const GetMaterialApp(home: SizedBox()));
      final controller = Get.put(PlacesController());
      await tester.pump(_demoraCarga);
      await tester.pumpAndSettle();
      expect(controller.estado.value, EstadoCarga.exito);

      // Control: con el controller vivo, pasar a error sí avisa.
      controller.estado.value = EstadoCarga.error;
      await tester.pump();
      expect(Get.isSnackbarOpen, isTrue);
      await tester.pumpAndSettle();
      await _esperarCierreDeAviso(tester);

      // Tras eliminarlo (llama a onClose), el worker ya no escucha.
      controller.estado.value = EstadoCarga.exito;
      expect(await Get.delete<PlacesController>(), isTrue);
      expect(Get.isRegistered<PlacesController>(), isFalse);
      controller.estado.value = EstadoCarga.error;
      await tester.pump();
      expect(Get.isSnackbarOpen, isFalse);
    });
  });

  group('Formulario Agregar lugar', () {
    Future<void> abrirFormulario(WidgetTester tester) async {
      await _abrirAppCargada(tester);
      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();
      expect(find.byType(AddPlaceScreen), findsOneWidget);
    }

    Finder campo(String etiqueta) =>
        find.widgetWithText(TextFormField, etiqueta);

    testWidgets('Guardar vacío muestra los tres errores y no agrega nada', (
      WidgetTester tester,
    ) async {
      await abrirFormulario(tester);
      final cantidadInicial = lugaresEjemplo.length;

      await tester.tap(find.widgetWithText(ElevatedButton, 'Guardar'));
      await tester.pump();

      expect(find.text('El nombre es obligatorio'), findsOneWidget);
      expect(find.text('La categoría es obligatoria'), findsOneWidget);
      expect(find.text('Escribe al menos 10 caracteres'), findsOneWidget);
      expect(lugaresEjemplo.length, cantidadInicial);
      expect(find.byType(AddPlaceScreen), findsOneWidget);
    });

    testWidgets('Completar y guardar vuelve a Inicio con el nuevo lugar', (
      WidgetTester tester,
    ) async {
      await abrirFormulario(tester);
      final cantidadInicial = lugaresEjemplo.length;
      const nombre = 'Mirador de Prueba';

      await tester.enterText(campo('Nombre del lugar'), nombre);
      await tester.enterText(campo('Categoría'), 'Miradores');
      await tester.enterText(
        campo('Descripción'),
        'Lugar sintético creado por la prueba del formulario.',
      );
      final controller = _controller();
      final cantidadEnController = controller.lugares.length;

      await tester.tap(find.widgetWithText(ElevatedButton, 'Guardar'));
      await tester.pump();
      // agregarLugar() actualiza la RxList: Obx redibuja Inicio sin pasar
      // por el estado de carga, ni durante ni después de la transición.
      expect(controller.estado.value, EstadoCarga.exito);
      expect(find.byType(LoadingView), findsNothing);
      await tester.pumpAndSettle(); // transición de Get.back()
      expect(find.byType(LoadingView), findsNothing);

      expect(find.byType(AddPlaceScreen), findsNothing);
      expect(controller.lugares.length, cantidadEnController + 1);
      expect(controller.lugares.last.nombre, nombre);
      // assignAll copia la lista: el lugar no queda duplicado.
      expect(
        controller.lugares.where((p) => p.nombre == nombre).length,
        1,
      );
      expect(find.byType(HomeScreen), findsOneWidget);
      expect(lugaresEjemplo.length, cantidadInicial + 1);
      expect(lugaresEjemplo.last.nombre, nombre);

      // El nuevo lugar queda al final de la lista: se desplaza hasta él.
      await tester.scrollUntilVisible(
        find.widgetWithText(PlaceCard, nombre),
        200,
        scrollable: find.byType(Scrollable),
      );
      expect(find.widgetWithText(PlaceCard, nombre), findsOneWidget);
      await _esperarCierreDeAviso(tester);
    });
  });

  testWidgets(
    'BienvenidaScreenClaudeDesign muestra el contenido y el SnackBar',
    (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: BienvenidaScreenClaudeDesign()),
      );

      // El título es texto enriquecido ("Explora" + "EC" en amarillo).
      expect(find.text('ExploraEC', findRichText: true), findsOneWidget);
      expect(find.text(_subtitulo), findsOneWidget);
      await _tocarEmpezarYVerSnackBar(tester);
    },
  );

  testWidgets('BienvenidaScreenClaudeDesign no se desborda en pantalla pequeña', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(320, 480);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      const MaterialApp(home: BienvenidaScreenClaudeDesign()),
    );

    expect(tester.takeException(), isNull);
    await tester.scrollUntilVisible(
      find.text('Empezar'),
      100,
      scrollable: find.byType(Scrollable),
    );
    expect(find.text('Empezar'), findsOneWidget);
  });
}
