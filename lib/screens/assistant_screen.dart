import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../controllers/auth_controller.dart';
import '../controllers/gastos_controller.dart';
import '../services/ai_assistant_service.dart';
import '../services/api_exception.dart';
import '../theme/app_theme.dart';
import '../widgets/sin_sesion_view.dart';

/// Asistente ExploraIA — Sesión 9. La persona pregunta por sus gastos; la app
/// pide el resumen por categoría al backend y se lo envía, junto con la
/// pregunta, al proxy del asistente. Si la respuesta propone una acción
/// (registrar un gasto), la app pide confirmación: la IA propone, la persona
/// decide y el backend valida.
class AssistantScreen extends StatefulWidget {
  const AssistantScreen({super.key});

  @override
  State<AssistantScreen> createState() => _AssistantScreenState();
}

class _AssistantScreenState extends State<AssistantScreen> {
  final _campo = TextEditingController();
  final AuthController _auth = Get.find<AuthController>();
  bool _cargando = false;
  String? _respuesta;
  String? _error;

  /// Al cambiar de sesión se borra lo que había en pantalla (pregunta,
  /// respuesta, error, carga): la siguiente persona no lo ve.
  late final Worker _alCambiarUsuario;

  @override
  void initState() {
    super.initState();
    _alCambiarUsuario = ever(_auth.usuario, (_) {
      if (!mounted) return;
      _cerrarDialogoDeConfirmacion();
      _campo.clear();
      setState(() {
        _cargando = false;
        _respuesta = null;
        _error = null;
      });
    });
  }

  @override
  void dispose() {
    _alCambiarUsuario.dispose();
    _campo.dispose();
    super.dispose();
  }

  /// Ruta del diálogo «Confirmar acción» mientras está abierto (Paso 5).
  Route<dynamic>? _rutaDialogo;

  /// Cierra solo el diálogo de confirmación (si sigue abierto), sin tocar
  /// otras pantallas: la propuesta era de la sesión anterior.
  void _cerrarDialogoDeConfirmacion() {
    final ruta = _rutaDialogo;
    if (ruta == null || !ruta.isActive) return;
    final navegador = ruta.navigator;
    if (navegador == null) return;
    if (ruta.isCurrent) {
      navegador.pop(false);
    } else {
      navegador.removeRoute(ruta, false);
    }
  }

  /// La operación sigue siendo de la sesión con que empezó y la pantalla existe.
  bool _vigente(int marca) => mounted && marca == _auth.marcaSesion;

  Future<void> _preguntar() async {
    final consulta = _campo.text.trim();
    if (consulta.isEmpty || _cargando) return;
    final marca = _auth.marcaSesion;
    setState(() {
      _cargando = true;
      _error = null;
      _respuesta = null;
    });
    try {
      // Por qué: el asistente solo necesita totales, no cada gasto. Se pide el
      // resumen por categoría al backend (con el token de tu sesión) y se envía
      // al proxy junto con la pregunta. La respuesta se muestra en pantalla.
      // TODO(sesion-09) Paso 4: descomenta las 3 líneas de abajo (conectar con el proxy).
      // Integración: tras cada espera se comprueba la marca de sesión; una
      // respuesta (o un error) de una sesión anterior se descarta.
      final resumen = await Get.find<GastosController>().obtenerResumen();
      if (!_vigente(marca)) return;
      final r = await Get.find<AiAssistantService>().preguntar(consulta, resumen);
      if (!_vigente(marca)) return;
      setState(() => _respuesta = r.respuesta);

      // Por qué: si la IA propone registrar un gasto, la app NO lo hace sola.
      // Muestra un diálogo y solo si la persona acepta se llama al backend.
      // TODO(sesion-09) Paso 5: descomenta la línea de abajo (pedir confirmación).
      // Integración: la confirmación recibe la marca de sesión de la pregunta.
      if (r.accion != null) await confirmarAccion(r.accion!, marca);
    } on ApiException catch (e) {
      if (_vigente(marca)) setState(() => _error = e.mensaje);
    } on AsistenteException catch (e) {
      // Un 401 del proxy llega aquí como mensaje: no cierra la sesión global
      // (pendiente distinguir su origen; ver PLACEHOLDERS.md).
      if (_vigente(marca)) setState(() => _error = e.mensaje);
    } finally {
      if (_vigente(marca)) setState(() => _cargando = false);
    }
  }

  /// Pregunta «¿Confirmas?» y, solo si la respuesta es sí, crea el gasto. El
  /// backend sigue validando (por ejemplo, el límite de 500 por categoría).
  /// Pide confirmación y solo si la persona acepta registra el gasto. La
  /// [marca] de sesión se comprueba antes de abrir el diálogo, después de la
  /// decisión y justo antes de crear: una propuesta de otra sesión nunca se
  /// registra (aunque haya vuelto a entrar la misma persona).
  Future<void> confirmarAccion(AccionPropuesta accion, int marca) async {
    if (!_vigente(marca)) return;
    final confirmado = await showDialog<bool>(
      context: context,
      builder: (dialogo) {
        _rutaDialogo = ModalRoute.of(dialogo);
        return AlertDialog(
          title: const Text('Confirmar acción'),
          content: Text(
              'La IA propone registrar: ${accion.descripcion} — ${accion.monto.toStringAsFixed(2)} en ${accion.categoria}. ¿Confirmas?'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogo, false), child: const Text('Cancelar')),
            FilledButton(onPressed: () => Navigator.pop(dialogo, true), child: const Text('Registrar')),
          ],
        );
      },
    );
    _rutaDialogo = null;
    if (confirmado != true || !_vigente(marca)) return;
    try {
      // `crear` reutiliza el controller de Gastos: recarga la primera página y
      // la caché; si la recarga falla, no lanza (el gasto no se repite).
      await Get.find<GastosController>().crear(accion.descripcion, accion.monto, accion.categoria);
      if (_vigente(marca)) {
        setState(() => _respuesta =
            'Listo: registré «${accion.descripcion}» por ${accion.monto.toStringAsFixed(2)} en ${accion.categoria}.');
      }
    } on ApiException catch (e) {
      if (_vigente(marca)) setState(() => _error = e.mensaje);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      if (!_auth.estaAutenticado) return SinSesionView(titulo: 'asistente'.tr);
      return _contenido(context);
    });
  }

  Widget _contenido(BuildContext context) {
    final colores = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text('asistente'.tr)),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: colores.secondaryContainer,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Row(
              children: [
                Icon(Icons.info_outline),
                SizedBox(width: AppSpacing.sm),
                Expanded(child: Text('Sugerencia de IA: verifica antes de decidir.')),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          TextField(
            controller: _campo,
            maxLines: 2,
            textInputAction: TextInputAction.send,
            onSubmitted: (_) => _cargando ? null : _preguntar(),
            decoration: const InputDecoration(
              labelText: 'Pregunta sobre tus gastos',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          // TODO(sesion-09) OPCIONAL Paso 9: descomenta las 17 líneas de abajo (preguntas sugeridas).
          // Wrap(
          //   spacing: AppSpacing.sm,
          //   runSpacing: AppSpacing.sm,
          //   children: [
          //     for (final sugerencia in const ['¿En qué categoría gasto más?', '¿Cuánto me queda en comida?', '¿Qué lugar barato de comida me recomiendas?'])
          //       ActionChip(
          //         label: Text(sugerencia),
          //         onPressed: _cargando
          //             ? null
          //             : () {
          //                 _campo.text = sugerencia;
          //                 _preguntar();
          //               },
          //       ),
          //   ],
          // ),
          // const SizedBox(height: AppSpacing.md),
          FilledButton.icon(
            onPressed: _cargando ? null : _preguntar,
            icon: _cargando
                ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.auto_awesome),
            label: const Text('Preguntar'),
          ),
          const SizedBox(height: AppSpacing.lg),
          if (_error != null)
            Text(_error!, style: TextStyle(color: colores.error))
          else if (_respuesta != null)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: Text(_respuesta!),
              ),
            )
          else if (!_cargando)
            Text('Escribe una pregunta sobre tus gastos y toca «Preguntar».',
                style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}
