import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

void main() {
  runApp(const ExploraEcApp());
}

// Colores del sistema de diseño "Andean Canopy" (Stitch).
class ExploraColors {
  static const background = Color(0xFFFAF8FF);
  static const primary = Color(0xFF004532);
  static const primaryContainer = Color(0xFF065F46);
  static const onPrimary = Color(0xFFFFFFFF);
  static const onSurface = Color(0xFF131B2E);
  static const onSurfaceVariant = Color(0xFF3F4944);
  static const surfaceLowest = Color(0xFFFFFFFF);
  static const surfaceLow = Color(0xFFF2F3FF);
  static const outlineVariant = Color(0xFFBEC9C2);
}

class ExploraEcApp extends StatelessWidget {
  const ExploraEcApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ExploraEC',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: ExploraColors.primaryContainer,
          primary: ExploraColors.primaryContainer,
          onPrimary: ExploraColors.onPrimary,
          surface: ExploraColors.background,
          onSurface: ExploraColors.onSurface,
        ),
        scaffoldBackgroundColor: ExploraColors.background,
        fontFamily: GoogleFonts.plusJakartaSans().fontFamily,
      ),
      // Temporal: versión Claude Design. Para volver a Stitch: BienvenidaScreen().
      home: const BienvenidaScreen(),
    );
  }
}

class BienvenidaScreen extends StatelessWidget {
  const BienvenidaScreen({super.key});

  void _onEmpezar(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Próximamente exploraremos lugares')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            // Scroll + altura mínima: en pantallas altas el botón queda abajo;
            // en pantallas pequeñas el contenido se desplaza sin desbordarse.
            return SingleChildScrollView(
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: IntrinsicHeight(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Column(
                      children: [
                        const Expanded(child: _Encabezado()),
                        Padding(
                          padding: const EdgeInsets.only(top: 16, bottom: 40),
                          child: _BotonEmpezar(
                            onPressed: () => _onEmpezar(context),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _Encabezado extends StatelessWidget {
  const _Encabezado();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 48),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const _IconoBrujula(),
          const SizedBox(height: 40),
          Text(
            'ExploraEC',
            textAlign: TextAlign.center,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 36,
              fontWeight: FontWeight.w800,
              height: 44 / 36,
              letterSpacing: -0.9,
              color: ExploraColors.onSurface,
            ),
          ),
          const SizedBox(height: 8),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 280),
            child: Text(
              'Descubre y guarda lugares cerca de ti',
              textAlign: TextAlign.center,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 17,
                fontWeight: FontWeight.w400,
                height: 1.625,
                color: ExploraColors.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _IconoBrujula extends StatelessWidget {
  const _IconoBrujula();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 112,
      height: 112,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: ExploraColors.surfaceLowest,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: ExploraColors.outlineVariant.withValues(alpha: 0.4),
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0F062C22),
            blurRadius: 32,
            offset: Offset(0, 12),
          ),
        ],
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: ExploraColors.surfaceLow.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Center(
          child: Icon(
            Icons.explore,
            size: 52,
            color: ExploraColors.primary,
            semanticLabel: 'Brújula',
          ),
        ),
      ),
    );
  }
}

class _BotonEmpezar extends StatelessWidget {
  const _BotonEmpezar({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 384),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          boxShadow: const [
            BoxShadow(
              color: Color(0x38065F46),
              blurRadius: 24,
              offset: Offset(0, 8),
            ),
          ],
        ),
        child: SizedBox(
          width: double.infinity,
          height: 56,
          child: FilledButton(
            onPressed: onPressed,
            style: FilledButton.styleFrom(
              backgroundColor: ExploraColors.primaryContainer,
              foregroundColor: ExploraColors.onPrimary,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              textStyle: GoogleFonts.plusJakartaSans(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.4,
              ),
            ),
            child: const Text('Empezar'),
          ),
        ),
      ),
    );
  }
}
