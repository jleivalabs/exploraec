import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../controllers/auth_controller.dart';
import '../controllers/gastos_controller.dart';
import '../controllers/places_controller.dart' show EstadoCarga;
import '../models/gasto.dart';
import '../services/api_exception.dart';
import '../theme/app_theme.dart';
import '../widgets/empty_view.dart';
import '../widgets/error_view.dart';
import '../widgets/loading_view.dart';
import '../widgets/sin_sesion_view.dart';
import 'gasto_form_screen.dart';
import 'pantalla_con_fallo.dart';
// Solo lo usan los bloques comentados del Paso 9.
// ignore_for_file: unused_import
import 'cambiar_password_screen.dart';

/// Sección «Gastos del viaje» — Sesión 6. Con sesión, la lista con los mismos
/// 3 estados de la Sesión 3 (cargando, vacío, error) que ya usa Inicio. Desde
/// la Sesión 7, si lo que se ve es la copia guardada en Hive, un
/// `MaterialBanner` lo avisa. Desde la Sesión 8, sin sesión se muestra
/// `SinSesionView` (el formulario vive en `LoginScreen`) y se agrega el CRUD.
class GastosScreen extends GetView<GastosController> {
  const GastosScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = Get.find<AuthController>();
    return Obx(() {
      // Por qué: los gastos son de una persona concreta; sin sesión el servidor
      // respondería 401. El `Obx` lee `estaAutenticado`, así que la pantalla
      // cambia sola al iniciar o cerrar sesión.
      // TODO(sesion-08) Paso 2: descomenta la línea de abajo (pantalla sin sesión).
      if (!auth.estaAutenticado) return const SinSesionView();
      return _buildGastos(context, auth);
    });
  }

  Widget _buildGastos(BuildContext context, AuthController auth) {
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
              if (valor == 'salir') auth.cerrarSesion();
              if (valor == 'invalidar') auth.invalidarTokenParaPruebas();
              // Por qué: pantalla opcional del Paso 9 (cambiar contraseña).
              // TODO(sesion-08) OPCIONAL Paso 9: descomenta la línea de abajo (abrir la pantalla).
              // if (valor == 'password') Get.to(() => const CambiarPasswordScreen());
              // Solo práctica (Sesión 10, Paso 2): provocan errores a propósito.
              if (valor == 'error_pantalla') Get.to(() => const PantallaConFallo());
              if (valor == 'error_async') {
                Future<void>.delayed(Duration.zero, () => throw StateError('Fallo asíncrono provocado a propósito'));
              }
              // Por qué: pantalla opcional con las licencias de los paquetes que usa la app.
              // TODO(sesion-10) OPCIONAL Paso 10: descomenta la línea de abajo (abrir «Acerca de»).
              // if (valor == 'acerca') showLicensePage(context: context, applicationName: 'ExploraEC', applicationVersion: '1.0.0');
            },
            itemBuilder: (context) => [
              // TODO(sesion-08) OPCIONAL Paso 9: descomenta la línea de abajo (opción del menú).
              // const PopupMenuItem(value: 'password', child: Text('Cambiar contraseña')),
              // TODO(sesion-10) OPCIONAL Paso 10: descomenta la línea de abajo (opción del menú).
              // const PopupMenuItem(value: 'acerca', child: Text('Acerca de')),
              const PopupMenuItem(value: 'salir', child: Text('Cerrar sesión')),
              // Solo en modo debug: herramientas de práctica (token inválido y
              // errores provocados de la Sesión 10).
              if (kDebugMode) ...const [
                PopupMenuItem(value: 'invalidar', child: Text('Invalidar token (solo práctica)')),
                PopupMenuItem(value: 'error_pantalla', child: Text('Error de pantalla (solo práctica)')),
                PopupMenuItem(value: 'error_async', child: Text('Error asíncrono (solo práctica)')),
              ],
            ],
          ),
        ],
      ),
      // Por qué: el botón «+» abre el formulario vacío para crear un gasto.
      // TODO(sesion-08) Paso 5: descomenta las 4 líneas de abajo (botón «+»).
      floatingActionButton: FloatingActionButton(
        onPressed: () => Get.to(() => const GastoFormScreen()),
        tooltip: 'Agregar gasto',
        child: const Icon(Icons.add),
      ),
      body: Obx(() {
        if (controller.estado.value == EstadoCarga.cargando) {
          return const LoadingView(mensaje: 'Cargando gastos...');
        }
        if (controller.estado.value == EstadoCarga.error) {
          // `iniciar` (no solo `cargarGastos`): el error pudo ser al abrir la
          // caja del usuario o al pedir las categorías.
          return ErrorView(
            mensaje: controller.mensajeError.value,
            onReintentar: controller.iniciar,
          );
        }
        // Por qué: `RefreshIndicator.onRefresh` exige una función que devuelva
        // un `Future` — el indicador gira hasta que ese `Future` termina.
        // `cargarGastos` ya es `async`, así que se pasa tal cual: no hace falta
        // escribir nada nuevo. Mientras recarga, el `Obx` de arriba muestra el
        // `LoadingView` de siempre; eso es lo esperado.
        // Sesión 10 (Paso 7): «Aún no registras gastos» solo es definitivo
        // si no quedan páginas; con páginas pendientes se muestra la lista
        // (aunque esté vacía) para que «Cargar más» siga a mano.
        final hayGastos = controller.gastos.isNotEmpty;
        final contenido = !hayGastos && !controller.hayMas
            ? const EmptyView(mensaje: 'Aún no registras gastos en este viaje')
            : RefreshIndicator(
                onRefresh: controller.cargarGastos,
                child: _buildLista(controller.gastosVisibles),
              );
        final partes = <Widget>[
          // Sesión 7 (Paso 2): la copia local va con su aviso, también cuando
          // la copia guardada es una lista vacía.
          if (controller.desdeCache.value) _buildAvisoCopia(),
          // Con gastos, con una categoría elegida o con páginas pendientes: así
          // un filtro activo siempre se ve y se puede quitar con «Todas»,
          // aunque la lista cargada esté vacía.
          if (hayGastos || controller.categoriaFiltro.value != null || controller.hayMas) _buildFiltro(),
        ];
        if (partes.isEmpty) return contenido;
        return Column(children: [...partes, Expanded(child: contenido)]);
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

  /// Chips de filtro (Sesión 10, Paso 7): «Todas» y una por categoría cargada.
  /// `ChoiceChip` ya anuncia a los lectores de pantalla si está seleccionado.
  Widget _buildFiltro() {
    final seleccion = controller.categoriaFiltro.value;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
      child: Row(
        children: [
          ChoiceChip(
            label: Text('filtro_todas'.tr),
            selected: seleccion == null,
            onSelected: (_) => controller.filtrar(null),
          ),
          for (final categoria in controller.categoriasCargadas)
            Padding(
              padding: const EdgeInsets.only(left: AppSpacing.sm),
              child: ChoiceChip(
                label: Text(categoria),
                selected: seleccion == categoria,
                onSelected: (_) => controller.filtrar(categoria),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildLista(List<Gasto> gastos) {
    // Se leen aquí (dentro del `Obx`), no en `itemBuilder`: `ListView.builder`
    // construye sus filas después, fuera del seguimiento de `Obx`.
    final conBoton = controller.hayMas;
    final cargandoMas = controller.cargandoMas.value;
    final fallo = controller.mensajeCargarMas.value;
    // Sesión 10 (Paso 7): hay gastos cargados, pero ninguno de la categoría
    // elegida; se dice así (no «Aún no registras gastos»).
    final seleccion = controller.categoriaFiltro.value;
    final sinCoincidencias = seleccion != null && gastos.isEmpty && controller.gastos.isNotEmpty;
    final filasExtra = sinCoincidencias ? 1 : 0;
    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      itemCount: gastos.length + filasExtra + (conBoton ? 1 : 0),
      itemBuilder: (context, i) {
        if (sinCoincidencias && i == 0) {
          return Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Text(
              'filtro_sin_coincidencias'.trParams({'categoria': seleccion}),
              textAlign: TextAlign.center,
            ),
          );
        }
        if (i == gastos.length + filasExtra) {
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
          // Por qué: tocar una fila abre el mismo formulario, ya relleno.
          // TODO(sesion-08) Paso 6: descomenta la línea de abajo (tocar para editar).
          onTap: () => Get.to(() => GastoFormScreen(gasto: g)),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(g.monto.toStringAsFixed(2), style: Theme.of(context).textTheme.titleMedium),
              // TODO(sesion-08) Paso 6: descomenta las 5 líneas de abajo (botón de eliminar).
              IconButton(
                icon: const Icon(Icons.delete_outline),
                tooltip: 'Eliminar',
                onPressed: () => confirmarEliminar(context, g),
              ),
            ],
          ),
        );
      },
    );
  }

  /// Pide confirmación antes de borrar; si el servidor falla, avisa con el
  /// mensaje que devolvió.
  Future<void> confirmarEliminar(BuildContext context, Gasto g) async {
    final confirmado = await showDialog<bool>(
      context: context,
      builder: (dialogo) => AlertDialog(
        title: Text('¿Eliminar "${g.descripcion}"?'),
        content: const Text('Esta acción no se puede deshacer.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogo, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(dialogo, true), child: const Text('Eliminar')),
        ],
      ),
    );
    if (confirmado != true) return;
    try {
      await controller.eliminar(g.id);
    } on ApiException catch (e) {
      Get.snackbar('No se pudo eliminar', e.mensaje);
    }
  }
}
