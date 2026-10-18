import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:exploraec/bienvenida_claude_design.dart';
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
  });

  // lugaresEjemplo es una lista global en memoria: se restaura tras cada
  // prueba para que agregar lugares no afecte a las demás.
  final lugaresOriginales = List<Place>.of(lugaresEjemplo);
  tearDown(() {
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

    // Solo pump(): al volver a Inicio, HomeScreen se crea de nuevo y
    // empieza otra carga (con animación infinita).
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
    expect(find.text('Próximamente: favoritos (Sesión 7)'), findsOneWidget);
    expect(indiceActual(), 2);

    await tocarPestana('Inicio');
    expect(find.byType(HomeScreen), findsOneWidget);
    await _esperarCarga(tester);
    expect(find.byType(FavoritesPlaceholderScreen), findsNothing);
    expect(find.text(lugaresEjemplo.first.nombre), findsOneWidget);
    expect(indiceActual(), 0);
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
      expect(find.textContaining(_mensajeError), findsOneWidget);
      expect(find.byType(PlaceCard), findsNothing);

      // El modo error sigue activo: reintentar vuelve a cargar y vuelve a fallar.
      await tester.tap(find.text('Reintentar'));
      await tester.pump();
      await _esperarCarga(tester);
      expect(find.byType(ErrorView), findsOneWidget);
      expect(find.textContaining(_mensajeError), findsOneWidget);
    });

    testWidgets('Tras un error, Simular normal recupera la lista', (
      WidgetTester tester,
    ) async {
      await _abrirAppCargada(tester);
      await _simular(tester, 'Simular: error');
      await _esperarCarga(tester);
      expect(find.byType(ErrorView), findsOneWidget);

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

      // El nodo de la tarjeta no tiene hijos que repitan el contenido.
      final nodo = tester.getSemantics(find.bySemanticsLabel(etiqueta(lugar)));
      final etiquetasHijas = <String>[];
      nodo.visitChildren((hijo) {
        etiquetasHijas.add(hijo.label);
        return true;
      });
      expect(etiquetasHijas, isEmpty);
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
      expect(find.textContaining(_mensajeError), findsOneWidget);
      expect(find.text('Reintentar'), findsOneWidget);
      expect(_temaDe(tester, find.byType(ErrorView)).brightness, Brightness.dark);
      expect(tester.takeException(), isNull);
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
      await tester.tap(find.widgetWithText(ElevatedButton, 'Guardar'));
      await tester.pump();

      // Al volver, HomeScreen llama a _cargar(): nueva carga simulada.
      await _esperarCarga(tester);
      expect(find.byType(AddPlaceScreen), findsNothing);
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
