import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../config/api_config.dart';
import '../controllers/gastos_controller.dart';
import '../controllers/places_controller.dart' show EstadoCarga;
import '../models/gasto.dart';
import '../theme/app_theme.dart';
import '../widgets/empty_view.dart';
import '../widgets/error_view.dart';
import '../widgets/loading_view.dart';

/// Sección «Gastos del viaje» — Sesión 6. Sin sesión muestra el formulario de
/// correo y contraseña; con sesión, la lista con los mismos 3 estados de la
/// Sesión 3 (cargando, vacío, error) que ya usa Inicio. Desde la Sesión 7, si
/// lo que se ve es la copia guardada en Hive, un `MaterialBanner` lo avisa.
class GastosScreen extends GetView<GastosController> {
  const GastosScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Obx(() => controller.sesionActiva.value ? _buildGastos(context) : _FormularioEntrada(controller: controller));
  }

  Widget _buildGastos(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Obx(() => Text('${'gastos'.tr} (${controller.totalEnServidor.value})')),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Recargar',
            onPressed: controller.cargarGastos,
          ),
          PopupMenuButton<String>(
            onSelected: (valor) {
              if (valor == 'salir') controller.salir();
              if (valor == 'invalidar') controller.invalidarTokenParaPruebas();
            },
            itemBuilder: (context) => const [
              PopupMenuItem(value: 'salir', child: Text('Cerrar sesión')),
              PopupMenuItem(value: 'invalidar', child: Text('Invalidar token (solo práctica)')),
            ],
          ),
        ],
      ),
      body: Obx(() {
        if (controller.estado.value == EstadoCarga.cargando) {
          return const LoadingView(mensaje: 'Cargando gastos...');
        }
        if (controller.estado.value == EstadoCarga.error) {
          return ErrorView(
            mensaje: controller.mensajeError.value,
            onReintentar: controller.cargarGastos,
          );
        }
        // Por qué: `RefreshIndicator.onRefresh` exige una función que devuelva
        // un `Future` — el indicador gira hasta que ese `Future` termina.
        // `cargarGastos` ya es `async`, así que se pasa tal cual: no hace falta
        // escribir nada nuevo. Mientras recarga, el `Obx` de arriba muestra el
        // `LoadingView` de siempre; eso es lo esperado.
        final contenido = controller.gastos.isEmpty
            ? const EmptyView(mensaje: 'Aún no registras gastos en este viaje')
            : RefreshIndicator(
                onRefresh: controller.cargarGastos,
                child: _buildLista(controller.gastos),
              );
        if (!controller.desdeCache.value) return contenido;
        // Sesión 7 (Paso 2): la copia local va con su aviso, también cuando
        // la copia guardada es una lista vacía.
        return Column(
          children: [
            _buildAvisoCopia(),
            Expanded(child: contenido),
          ],
        );
      }),
    );
  }

  /// Banner del curso («Sin conexión — mostrando tus gastos guardados») con
  /// la última sincronización y «Reintentar». Ajuste propio: si la copia es
  /// parcial (se guardaron menos gastos que el total que informó el
  /// servidor), lo dice, para no presentarla como la lista completa.
  Widget _buildAvisoCopia() {
    final guardados = controller.gastos.length;
    final total = controller.totalEnServidor.value;
    final parcial = guardados < total;
    return MaterialBanner(
      content: Text(
        'Sin conexión — mostrando tus gastos guardados '
        '(última sincronización: ${controller.ultimaSincronizacion})'
        '${parcial ? '. Copia parcial: $guardados de $total gastos guardados.' : ''}',
      ),
      leading: const Icon(Icons.cloud_off),
      actions: [
        TextButton(
          onPressed: controller.cargarGastos,
          child: const Text('Reintentar'),
        ),
      ],
    );
  }

  Widget _buildLista(List<Gasto> gastos) {
    // Se leen aquí (dentro del `Obx`), no en `itemBuilder`: `ListView.builder`
    // construye sus filas después, fuera del seguimiento de `Obx`.
    final conBoton = controller.hayMas;
    final cargandoMas = controller.cargandoMas.value;
    final fallo = controller.mensajeCargarMas.value;
    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      itemCount: gastos.length + (conBoton ? 1 : 0),
      itemBuilder: (context, i) {
        if (i == gastos.length) {
          return Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (fallo.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                    child: Text(
                      'No se pudieron cargar más gastos: $fallo',
                      style: TextStyle(color: Theme.of(context).colorScheme.error),
                    ),
                  ),
                OutlinedButton(
                  onPressed: cargandoMas ? null : controller.cargarMas,
                  child: cargandoMas
                      ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                      : Text(fallo.isEmpty ? 'Cargar más' : 'Reintentar cargar más'),
                ),
              ],
            ),
          );
        }
        final g = gastos[i];
        return ListTile(
          title: Text(g.descripcion),
          subtitle: Text('${g.categoria} · ${g.fecha}'),
          trailing: Text(g.monto.toStringAsFixed(2), style: Theme.of(context).textTheme.titleMedium),
        );
      },
    );
  }
}

class _FormularioEntrada extends StatefulWidget {
  final GastosController controller;
  const _FormularioEntrada({required this.controller});

  @override
  State<_FormularioEntrada> createState() => _FormularioEntradaState();
}

class _FormularioEntradaState extends State<_FormularioEntrada> {
  final _email = TextEditingController();
  final _password = TextEditingController();

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    return Scaffold(
      appBar: AppBar(title: Text('gastos'.tr)),
      body: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Obx(() => ListView(
              children: [
                const Text('Entra para ver los gastos de tu viaje. Si tu correo es nuevo, se crea la cuenta.'),
                const SizedBox(height: AppSpacing.lg),
                TextField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(labelText: 'Correo', border: OutlineInputBorder()),
                ),
                const SizedBox(height: AppSpacing.md),
                TextField(
                  controller: _password,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: 'Contraseña (8 a 72 caracteres)', border: OutlineInputBorder()),
                ),
                const SizedBox(height: AppSpacing.md),
                if (c.mensajeAuth.value.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.md),
                    child: Text(c.mensajeAuth.value, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                  ),
                FilledButton(
                  onPressed: c.autenticando.value ? null : () => c.entrar(_email.text.trim(), _password.text),
                  child: c.autenticando.value
                      ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Entrar'),
                ),
                const SizedBox(height: AppSpacing.lg),
                Text('Servidor: ${ApiConfig.baseUrl}', style: Theme.of(context).textTheme.bodySmall),
              ],
            )),
      ),
    );
  }
}
