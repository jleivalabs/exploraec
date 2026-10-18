import 'package:flutter/material.dart';
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
import 'package:exploraec/widgets/place_card.dart';

const _subtitulo = 'Descubre y guarda lugares cerca de ti';
const _mensaje = 'Próximamente exploraremos lugares';

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
    await tester.pumpWidget(const ExploraEcApp());

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
    await tester.pumpWidget(const ExploraEcApp());

    Future<void> tocarPestana(String etiqueta) async {
      await tester.tap(
        find.descendant(
          of: find.byType(BottomNavigationBar),
          matching: find.text(etiqueta),
        ),
      );
      await tester.pumpAndSettle();
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
    expect(find.byType(FavoritesPlaceholderScreen), findsNothing);
    expect(find.text(lugaresEjemplo.first.nombre), findsOneWidget);
    expect(indiceActual(), 0);
  });

  group('Formulario Agregar lugar', () {
    Future<void> abrirFormulario(WidgetTester tester) async {
      await tester.pumpWidget(const ExploraEcApp());
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
      await tester.pumpAndSettle();

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
