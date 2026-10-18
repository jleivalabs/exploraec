import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

// Colores de la propuesta de Claude Design (independientes del tema de Stitch).
class _ClaudeColors {
  static const background = Color(0xFF0B2A33);
  static const accent = Color(0xFFF5C04A);
  static const title = Color(0xFFF3F1EA);
  static const subtitle = Color(0xFFB9C7C9);
  static const iconCircle = Color(0xFF12404B);
  static const iconBorder = Color(0xFF1E5865);
}

class BienvenidaScreenClaudeDesign extends StatelessWidget {
  const BienvenidaScreenClaudeDesign({super.key});

  void _onEmpezar(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Próximamente exploraremos lugares')),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Fondo oscuro: íconos claros en la barra de estado.
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: _ClaudeColors.background,
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
                      padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Expanded(child: _Encabezado()),
                          _BotonEmpezar(onPressed: () => _onEmpezar(context)),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _Encabezado extends StatelessWidget {
  const _Encabezado();

  @override
  Widget build(BuildContext context) {
    final tituloStyle = GoogleFonts.sora(
      fontSize: 40,
      fontWeight: FontWeight.w700,
      height: 1.1,
      letterSpacing: -0.8,
      color: _ClaudeColors.title,
    );

    return Padding(
      padding: const EdgeInsets.only(top: 48, bottom: 24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const _IconoPin(),
          const SizedBox(height: 36),
          Text.rich(
            const TextSpan(
              text: 'Explora',
              children: [
                TextSpan(
                  text: 'EC',
                  style: TextStyle(color: _ClaudeColors.accent),
                ),
              ],
            ),
            style: tituloStyle,
            textAlign: TextAlign.center,
            semanticsLabel: 'ExploraEC',
          ),
          const SizedBox(height: 12),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 270),
            child: Text(
              'Descubre y guarda lugares cerca de ti',
              textAlign: TextAlign.center,
              style: GoogleFonts.dmSans(
                fontSize: 18,
                fontWeight: FontWeight.w400,
                height: 1.5,
                color: _ClaudeColors.subtitle,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _IconoPin extends StatelessWidget {
  const _IconoPin();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 96,
      height: 96,
      decoration: BoxDecoration(
        color: _ClaudeColors.iconCircle,
        shape: BoxShape.circle,
        border: Border.all(color: _ClaudeColors.iconBorder),
      ),
      child: const Icon(
        Icons.location_on_outlined,
        size: 48,
        color: _ClaudeColors.accent,
        semanticLabel: 'Ubicación',
      ),
    );
  }
}

class _BotonEmpezar extends StatelessWidget {
  const _BotonEmpezar({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 56,
      child: FilledButton(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: _ClaudeColors.accent,
          foregroundColor: _ClaudeColors.background,
          shape: const StadiumBorder(),
          textStyle: GoogleFonts.dmSans(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.17,
          ),
        ),
        child: const Text('Empezar'),
      ),
    );
  }
}
