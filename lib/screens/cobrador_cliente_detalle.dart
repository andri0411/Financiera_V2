// ignore_for_file: use_build_context_synchronously
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:blue_thermal_printer/blue_thermal_printer.dart';
import 'package:flutter/services.dart';

class CobradorClienteDetalleScreen extends StatefulWidget {
  final Map<String, dynamic> cliente;
  final Map<String, dynamic> prestamo;
  final bool enRuta;

  const CobradorClienteDetalleScreen({
    super.key,
    required this.cliente,
    required this.prestamo,
    this.enRuta = true,
  });

  @override
  State<CobradorClienteDetalleScreen> createState() => _CobradorClienteDetalleScreenState();
}

class _CobradorClienteDetalleScreenState extends State<CobradorClienteDetalleScreen> {
  final formatter = NumberFormat.currency(locale: 'es_MX', symbol: '\$');
  bool _isLoading = true;
  bool _isProcessing = false;
  bool _atendido = false;
  String _resultadoAccion = '';
  Map<String, dynamic>? _prestamo;
  List<Map<String, dynamic>> _cuotas = [];
  
  // Configuración del ticket y Bluetooth
  final BlueThermalPrinter _bluetooth = BlueThermalPrinter.instance;
  String _ticketHeader = 'FINANCIERA REGIONAL';
  String _ticketPhone = '999-107-9110';
  String _ticketFooter = 'Gracias por su Puntualidad';
  String _nombreCobrador = '';

  @override
  void initState() {
    super.initState();
    _prestamo = Map.from(widget.prestamo);
    _fetchData();
    _fetchTicketConfig();
  }

  Future<void> _fetchTicketConfig() async {
    try {
      final res = await Supabase.instance.client
          .from('configuracion')
          .select('ticket_header, ticket_phone, ticket_footer')
          .eq('id', 1)
          .single();
      // Obtener nombre completo del cobrador actual
      final userId = Supabase.instance.client.auth.currentUser?.id;
      String nombreCob = '';
      if (userId != null) {
        final cobrador = await Supabase.instance.client
            .from('perfiles')
            .select('nombre_completo')
            .eq('id', userId)
            .maybeSingle();
        // Intentar nombre_completo
        nombreCob = cobrador?['nombre_completo'] ?? '';
      }
      if (mounted) {
        setState(() {
          _ticketHeader = res['ticket_header'] ?? 'FINANCIERA REGIONAL';
          _ticketPhone = res['ticket_phone'] ?? '999-107-9110';
          _ticketFooter = res['ticket_footer'] ?? 'Gracias por su Puntualidad';
          _nombreCobrador = nombreCob;
        });
      }
    } catch (_) {}
  }

  Future<void> _fetchData() async {
    setState(() => _isLoading = true);
    try {
      final res = await Supabase.instance.client
          .from('prestamos')
          .select()
          .eq('id', widget.prestamo['id'])
          .single();
      final cuotas = await Supabase.instance.client
          .from('cuotas')
          .select()
          .eq('prestamo_id', widget.prestamo['id'])
          .order('numero_cuota', ascending: true);

      // Verificar si ya fue atendido hoy
      final hoy = DateTime.now().toIso8601String().split('T')[0];
      final atencionHoy = await Supabase.instance.client
          .from('atencion_diaria')
          .select()
          .eq('cliente_id', widget.cliente['id'])
          .eq('fecha', hoy)
          .maybeSingle();

      setState(() {
        _prestamo = Map<String, dynamic>.from(res);
        _cuotas = List<Map<String, dynamic>>.from(cuotas);
        // Si ya fue atendido hoy (cobrado o no_pago), mostrar banner
        if (atencionHoy != null &&
            (atencionHoy['estado'] == 'cobrado' || atencionHoy['estado'] == 'no_pago')) {
          _atendido = true;
          _resultadoAccion = atencionHoy['estado'];
        }
      });
    } catch (e) {
      _showSnack('Error al cargar datos: $e', isError: true);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // â”€â”€ Helpers â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  Map<String, dynamic>? _cuotaHoy() {
    final hoy = DateTime.now();
    final hoyDate = DateTime(hoy.year, hoy.month, hoy.day);
    
    // 1. Primero buscar la cuota normal de hoy (o pasada que siga pendiente)
    for (var c in _cuotas) {
      if (c['estado_pago'] == 'pendiente') {
        final vencimiento = DateTime.tryParse(c['fecha_vencimiento'] ?? '');
        if (vencimiento == null) continue;
        final vencDate = DateTime(vencimiento.year, vencimiento.month, vencimiento.day);
        
        if (!vencDate.isAfter(hoyDate)) {
          return c;
        }
      }
    }
    
    // 2. Si ya no hay cuotas pendientes para hoy (ej. llegamos al final del plazo),
    // empezamos a cobrar las cuotas que se quedaron rezagadas (vencidas).
    for (var c in _cuotas) {
      if (c['estado_pago'] == 'vencido') {
        return c;
      }
    }
    
    return null;
  }

  bool _tieneAdelantos() {
    final cuota = _cuotaHoy();
    if (cuota == null) return true; // No hay cuotas pendientes (liquidado o adelantó todo)
    final vencimiento = DateTime.tryParse(cuota['fecha_vencimiento'] ?? '');
    if (vencimiento == null) return false;
    
    final hoy = DateTime.now();
    final hoyDate = DateTime(hoy.year, hoy.month, hoy.day);
    final vencDate = DateTime(vencimiento.year, vencimiento.month, vencimiento.day);
    
    // Tiene adelantos si su próxima cuota pendiente es para un día futuro
    return vencDate.isAfter(hoyDate);
  }

  void _showSnack(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: isError ? Colors.red : const Color(0xFF22C55E),
      behavior: SnackBarBehavior.floating,
    ));
  }

  // â”€â”€ Imprimir Ticket â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  Future<void> _imprimirTicket({
    required double montoPagado,
    int cuotasQueSePagan = 1,
    bool esLiquidacion = false,
    bool soloMora = false,
    double moraPagada = 0,
  }) async {
    try {
      bool? connected = await _bluetooth.isConnected;
      if (connected != true) return; // Si no hay impresora, no interrumpir

      final p = _prestamo!;
      final ahora = DateTime.now();
      final dateF = DateFormat('dd/MM/yy').format(ahora);
      final timeF = DateFormat('HH:mm').format(ahora);

      // Conteo ANTES de actualizar => cuotasPagadas ya incluye el pago que acabamos de hacer
      final cuotasPagadas = _cuotas.where((c) => c['estado_pago'] == 'pagado').length;
      // Plazo total (cuántos pagos tiene el crédito)
      final plazo = (p['plazo_dias'] ?? _cuotas.length) as int;
      // Pagos restantes DESPUí‰S de este pago
      final cuotasRestantes = plazo - cuotasPagadas;

      final cuotaDiaria = (p['cuota_diaria'] ?? 0).toDouble();
      final atrasosConteo = (p['cuotas_atrasadas_conteo'] ?? 0) as int;
      final faltante = (p['faltante_actual'] ?? 0).toDouble();
      final mora = (p['mora_acumulada'] ?? 0).toDouble();
      final totalFaltaLiquidar = faltante + mora;

      final nombreCliente = widget.cliente['nombre_completo'] ?? '';

      // Intentar leer fecha_fin, si no existe intentar fecha_finalizacion
      String fechaVencimiento = '--';
      final rawFecha = p['fecha_fin'] ?? p['fecha_finalizacion'];
      if (rawFecha != null) {
        try {
          fechaVencimiento = DateFormat('dd/MM/yyyy').format(DateTime.parse(rawFecha.toString()));
        } catch (_) {}
      }

      // â”€â”€ ENCABEZADO â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
      for (String line in _ticketHeader.toUpperCase().split('\n')) {
        final l = line.trim();
        if (l.isNotEmpty) _bluetooth.printCustom(l, 2, 1);
      }
      
      if (_ticketPhone.isNotEmpty) {
        _bluetooth.printCustom('TEL $_ticketPhone', 1, 1);
      }
      _bluetooth.printNewLine();

      // â”€â”€ DATOS DEL CLIENTE â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
      _bluetooth.printCustom('FECHA: $dateF   HORA: $timeF', 1, 0);
      final nombreCorto = nombreCliente.length > 24 ? nombreCliente.substring(0, 24) : nombreCliente;
      _bluetooth.printCustom('CLIENTE: $nombreCorto', 1, 0);
      _bluetooth.printCustom('PAGO DIARIO:\$${cuotaDiaria.toStringAsFixed(0)} PLAZO $plazo', 1, 0);
      _bluetooth.printCustom('VENCIMIENTO: $fechaVencimiento', 1, 0);
      if (_nombreCobrador.isNotEmpty) {
        _bluetooth.printCustom('LE ATENDIO: $_nombreCobrador', 1, 0);
      }

      _bluetooth.printCustom('--------------------------------', 1, 1);
      _bluetooth.printCustom('DETALLES DEL PAGO', 1, 1);
      _bluetooth.printCustom('--------------------------------', 1, 1);

      // PAGOS REALIZADOS
      if (soloMora) {
        _bluetooth.printLeftRight('PAGO APLICADO A:', 'MORA', 1);
        _bluetooth.printCustom('USTED ESTA PAGANDO:', 1, 0);
        _bluetooth.printCustom('SOLO MORATORIOS', 1, 0);
      } else {
        _bluetooth.printLeftRight('PAGOS REALIZADOS:', '$cuotasQueSePagan', 1);
        _bluetooth.printCustom('USTED ESTA EN SU PAGO:', 1, 0);
        if (esLiquidacion) {
          _bluetooth.printCustom('#$plazo DE $plazo PAGO', 1, 0);
        } else {
          // cuotasPagadas ya incluye las cuotas que se están pagando en esta transacción
          _bluetooth.printCustom('#$cuotasPagadas DE $plazo PAGO', 1, 0);
        }
      }
      
      if (esLiquidacion && moraPagada > 0) {
        _bluetooth.printLeftRight('MORA INCLUIDA:', '\$${moraPagada.toStringAsFixed(2)}', 1);
      }
      
      _bluetooth.printLeftRight('IMPORTE:', '\$${montoPagado.toStringAsFixed(2)}', 1);

      _bluetooth.printCustom('--------------------------------', 1, 1);
      _bluetooth.printCustom('SALDO', 1, 1);
      _bluetooth.printCustom('--------------------------------', 1, 1);

      // Pagos restantes debe ser la cantidad de cuotas pendientes reales
      final cuotasRestantesReal = _cuotas.where((c) => c['estado_pago'] == 'pendiente').length;

      if (esLiquidacion) {
        if (mora > 0 || atrasosConteo > 0) {
          _bluetooth.printLeftRight('DEBE MORATORIAS:', '\$${mora.toStringAsFixed(2)}', 1);
          _bluetooth.printLeftRight('PAGOS ATRASADOS:', '$atrasosConteo', 1);
        }
        _bluetooth.printLeftRight('PAGOS RESTANTES:', '0', 1);
        _bluetooth.printLeftRight('FALTA LIQUIDAR:', '\$0.00', 1);
      } else {
        _bluetooth.printLeftRight('DEBE MORATORIAS:', '\$${mora.toStringAsFixed(2)}', 1);
        _bluetooth.printLeftRight('PAGOS ATRASADOS:', '$atrasosConteo', 1);
        _bluetooth.printLeftRight('PAGOS RESTANTES:', '$cuotasRestantesReal', 1);
        _bluetooth.printLeftRight('FALTA LIQUIDAR:', '\$${totalFaltaLiquidar.toStringAsFixed(2)}', 1);
      }

      _bluetooth.printNewLine();
      _bluetooth.printCustom(_ticketFooter, 1, 1);
      _bluetooth.printNewLine();
      _bluetooth.paperCut();
    } on PlatformException catch (_) {
      // Ignorar error de impresión para no bloquear el flujo de cobro
    } catch (_) {}
  }


  Future<bool> _confirm(String title, String body, {Color? confirmColor}) async {
    return await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF09305A))),
        content: Text(body),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: confirmColor ?? const Color(0xFF09305A),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('Confirmar', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    ) ?? false;
  }

  // â”€â”€ Acciones â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  Future<void> _cobrar() async {
    final cuota = _cuotaHoy();
    if (cuota == null) { _showSnack('No hay cuota pendiente para hoy.', isError: true); return; }
    final cuotaDiaria = (_prestamo?['cuota_diaria'] ?? 0).toDouble();
    final ok = await _confirm('Cobrar Cuota', '¿Confirmas cobrar ${formatter.format(cuotaDiaria)} a este cliente?');
    if (!ok) return;
    setState(() => _isProcessing = true);
    try {
      final cobradorId = Supabase.instance.client.auth.currentUser!.id;
      final fechaLocal = DateTime.now().toLocal().toIso8601String().split('T')[0];
      await Supabase.instance.client.rpc('fn_procesar_pago', params: {
        'p_prestamo_id': _prestamo!['id'],
        'p_cuota_id': cuota['id'],
        'p_monto_total': cuotaDiaria,
        'p_monto_base': cuotaDiaria,
        'p_monto_mora': 0,
        'p_monto_penalizacion': 0,
        'p_cobrador_id': cobradorId,
        'p_fecha_local': fechaLocal,
      });
      // Recargar datos frescos para ticket
      await _fetchData();
      // Imprimir ticket después del cobro
      await _imprimirTicket(montoPagado: cuotaDiaria);
      if (mounted) setState(() { _atendido = true; _resultadoAccion = 'cobrado'; });
    } catch (e) {
      _showSnack('Error al registrar cobro: \$e', isError: true);
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _noPago() async {
    final ok = await _confirm(
      'No Pagó',
      _tieneAdelantos()
          ? 'El cliente tiene cuotas adelantadas, por lo que NO se generará mora ni atraso. ¿Continuar?'
          : 'Esto marcará al cliente como No Pagó y generará una mora y cuota atrasada.',
      confirmColor: Colors.red,
    );
    if (!ok) return;
    setState(() => _isProcessing = true);
    try {
      final cobradorId = Supabase.instance.client.auth.currentUser!.id;
      final fechaLocal = DateTime.now().toLocal().toIso8601String().split('T')[0];
      if (_tieneAdelantos()) {
        await Supabase.instance.client.from('atencion_diaria').upsert({
          'cliente_id': widget.cliente['id'],
          'cobrador_id': cobradorId,
          'estado': 'no_pago',
          'fecha': fechaLocal,
        }, onConflict: 'cliente_id,fecha');
      } else {
        await Supabase.instance.client.rpc('fn_registrar_no_pago', params: {
          'p_prestamo_id': _prestamo!['id'],
          'p_cobrador_id': cobradorId,
          'p_fecha_local': fechaLocal,
        });
      }
      // RECARGAR DATOS PARA QUE APAREZCA EL BOTí“N DE "PAGAR MORA" INMEDIATAMENTE
      await _fetchData();
      if (mounted) setState(() { _atendido = true; _resultadoAccion = 'no_pago'; });
    } catch (e) {
      _showSnack('Error: $e', isError: true);
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }
  Future<void> _pasar() async {
    final ok = await _confirm('Pasar', 'El cliente pasará al final de la ruta. No se generará mora ni atraso.');
    if (!ok) return;
    if (mounted) Navigator.pop(context, 'pasar');
  }

  Future<void> _pagarMoraAtraso() async {
    final mora = (_prestamo?['mora_acumulada'] ?? 0).toDouble();
    final atrasosConteo = (_prestamo?['cuotas_atrasadas_conteo'] ?? 0) as int;

    if (mora <= 0) {
      _showSnack('No hay mora pendiente por pagar.', isError: true);
      return;
    }

    // Calcular mora por día
    final maxMoras = atrasosConteo > 0 ? atrasosConteo : 1;
    int morasSeleccionadas = maxMoras;
    final moraPorDia = mora / maxMoras;

    final result = await showDialog<int>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(builder: (context, setDialogState) {
          final total = morasSeleccionadas * moraPorDia;
          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: const Text('Pagar Mora', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF09305A))),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Días de mora a pagar (de $maxMoras):', style: const TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconButton(
                      onPressed: morasSeleccionadas > 1 
                        ? () => setDialogState(() => morasSeleccionadas--) 
                        : null,
                      icon: const Icon(Icons.remove_circle_outline, size: 36),
                      color: const Color(0xFFDC2626),
                    ),
                    const SizedBox(width: 16),
                    Text(
                      morasSeleccionadas.toString(),
                      style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Color(0xFF09305A)),
                    ),
                    const SizedBox(width: 16),
                    IconButton(
                      onPressed: morasSeleccionadas < maxMoras 
                        ? () => setDialogState(() => morasSeleccionadas++) 
                        : null,
                      icon: const Icon(Icons.add_circle_outline, size: 36),
                      color: const Color(0xFFDC2626),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                const Divider(),
                Text('Total a cobrar: ${formatter.format(total)}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Color(0xFF09305A))),
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, null), child: const Text('Cancelar')),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx, morasSeleccionadas),
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFDC2626), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                child: const Text('Confirmar Cobro', style: TextStyle(color: Colors.white)),
              ),
            ],
          );
        });
      },
    );

    if (result == null) return;

    final totalAPagar = result * moraPorDia;

    final cuotasPendientes = _cuotas.where((c) => c['estado_pago'] != 'pagado').toList();
    final cuotaIdRef = cuotasPendientes.isNotEmpty ? cuotasPendientes.first['id'] : _cuotas.last['id'];

    setState(() => _isProcessing = true);
    try {
      final cobradorId = Supabase.instance.client.auth.currentUser!.id;
      final fechaLocal = DateTime.now().toLocal().toIso8601String().split('T')[0];
      
      await Supabase.instance.client.rpc('fn_procesar_pago', params: {
        'p_prestamo_id': _prestamo!['id'],
        'p_cuota_id': cuotaIdRef,
        'p_monto_total': totalAPagar,
        'p_monto_base': 0, // No se pagan cuotas
        'p_monto_mora': totalAPagar,
        'p_monto_penalizacion': 0,
        'p_cobrador_id': cobradorId,
        'p_fecha_local': fechaLocal,
      });

      if (mounted) setState(() { _atendido = true; _resultadoAccion = 'cobrado'; });
      
      // Recargar datos para tener los montos actualizados en el ticket
      await _fetchData();
      
      // Imprimir el ticket de solo mora
      await _imprimirTicket(
        montoPagado: totalAPagar.toDouble(),
        soloMora: true,
      );

      _showSnack('Cobro de mora registrado exitosamente.');
    } catch (e) {
      _showSnack('Error: $e', isError: true);
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _adelantarPagos() async {
    int cuotasNum = 1;
    final cuotaDiaria = (_prestamo?['cuota_diaria'] ?? 0).toDouble();
    final atrasosConteo = (_prestamo?['cuotas_atrasadas_conteo'] ?? 0) as int;

    // Permitir adelantar/pagar múltiple cualquier cuota no pagada
    final cuotasFuturas = _cuotas.where((c) => c['estado_pago'] != 'pagado').toList();

    if (cuotasFuturas.isEmpty) {
      _showSnack('No hay cuotas para procesar.', isError: true);
      return;
    }
    final maxCuotas = cuotasFuturas.length;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(builder: (ctx2, setD) {
          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: const Text('Adelantar Pagos', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF09305A))),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (atrasosConteo > 0)
                  Container(
                    padding: const EdgeInsets.all(12),
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFFBEB),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFFFEF08A)),
                    ),
                    child: Row(children: [
                      const Icon(Icons.info_outline, color: Color(0xFFD97706), size: 16),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Este cliente tiene $atrasosConteo cuota(s) atrasada(s). Puedes usar esta opción para recuperar pagos atrasados rápidamente o adelantar futuras.',
                          style: const TextStyle(color: Color(0xFF92400E), fontSize: 12),
                        ),
                      ),
                    ]),
                  ),
                const Text('¿Cuántas cuotas desea adelantar?'),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.remove_circle_outline),
                      onPressed: () { if (cuotasNum > 1) setD(() => cuotasNum--); },
                    ),
                    Text('$cuotasNum', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Color(0xFF09305A))),
                    IconButton(
                      icon: const Icon(Icons.add_circle_outline),
                      onPressed: () { if (cuotasNum < maxCuotas) setD(() => cuotasNum++); },
                    ),
                  ],
                ),
                Text('Total a pagar: ${formatter.format(cuotasNum * cuotaDiaria)}',
                    style: const TextStyle(color: Colors.grey, fontSize: 13)),
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF09305A), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                child: const Text('Confirmar', style: TextStyle(color: Colors.white)),
              ),
            ],
          );
        });
      },
    ) ?? false;

    if (!ok) return;
    setState(() => _isProcessing = true);
    try {
      final cobradorId = Supabase.instance.client.auth.currentUser!.id;
      final fechaLocal = DateTime.now().toLocal().toIso8601String().split('T')[0];
      final cuotasAAdelantar = cuotasFuturas.take(cuotasNum).toList();
      for (var cuota in cuotasAAdelantar) {
        await Supabase.instance.client.rpc('fn_procesar_pago', params: {
          'p_prestamo_id': _prestamo!['id'],
          'p_cuota_id': cuota['id'],
          'p_monto_total': cuotaDiaria,
          'p_monto_base': cuotaDiaria,
          'p_monto_mora': 0,
          'p_monto_penalizacion': 0,
          'p_cobrador_id': cobradorId,
          'p_fecha_local': fechaLocal,
        });
      }
      // Recargar datos frescos para ticket
      await _fetchData();
      // Imprimir ticket
      await _imprimirTicket(
        montoPagado: (cuotasNum * cuotaDiaria).toDouble(),
        cuotasQueSePagan: cuotasNum,
      );
      
      _showSnack('$cuotasNum cuota(s) adelantada(s) exitosamente.');
    } catch (e) {
      _showSnack('Error: $e', isError: true);
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _liquidarCredito() async {
    final faltante = (_prestamo?['faltante_actual'] ?? 0).toDouble();
    final mora = (_prestamo?['mora_acumulada'] ?? 0).toDouble();
    final totalALiquidar = faltante + mora;

    final ok = await _confirm('Liquidar Crédito', '¿Deseas liquidar este crédito por ${formatter.format(totalALiquidar)}?\n\nEsto registrará el cobro del saldo pendiente y moras.');
    if (!ok) return;

    final cuotasPendientes = _cuotas.where((c) => c['estado_pago'] != 'pagado').toList();

    setState(() => _isProcessing = true);
    try {
      final cobradorId = Supabase.instance.client.auth.currentUser!.id;
      final fechaLocal = DateTime.now().toLocal().toIso8601String().split('T')[0];
      
      if (cuotasPendientes.isEmpty) {
        // En caso excepcional sin cuotas por pagar pero con saldo
        await Supabase.instance.client.rpc('fn_procesar_pago', params: {
          'p_prestamo_id': _prestamo!['id'],
          'p_cuota_id': _cuotas.last['id'],
          'p_monto_total': totalALiquidar,
          'p_monto_base': faltante,
          'p_monto_mora': mora,
          'p_monto_penalizacion': 0,
          'p_cobrador_id': cobradorId,
          'p_fecha_local': fechaLocal,
        });
      } else {
        // Pagamos todas las cuotas individualmente para mantener el historial
        for (var cuota in cuotasPendientes) {
           final montoC = (cuota['monto_cuota'] ?? 0).toDouble();
           final bool esPrimera = cuota == cuotasPendientes.first;
           await Supabase.instance.client.rpc('fn_procesar_pago', params: {
              'p_prestamo_id': _prestamo!['id'],
              'p_cuota_id': cuota['id'],
              'p_monto_total': montoC + (esPrimera ? mora : 0),
              'p_monto_base': montoC,
              'p_monto_mora': esPrimera ? mora : 0,
              'p_monto_penalizacion': 0,
              'p_cobrador_id': cobradorId,
              'p_fecha_local': fechaLocal,
           });
        }
      }

      await Supabase.instance.client.from('prestamos').update({'estado': 'liquidado'}).eq('id', _prestamo!['id']);

      if (mounted) setState(() { _atendido = true; _resultadoAccion = 'cobrado'; });
      
      // Recargar datos frescos para ticket
      await _fetchData();
      // Imprimir ticket
      await _imprimirTicket(
        montoPagado: totalALiquidar,
        cuotasQueSePagan: cuotasPendientes.length,
        esLiquidacion: true,
        moraPagada: mora,
      );

      _showSnack('Crédito liquidado exitosamente.');
    } catch (e) {
      _showSnack('Error: $e', isError: true);
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _reimprimirAccionesHoy() async {
    setState(() => _isProcessing = true);
    try {
      final pId = _prestamo!['id'];
      final hoy = DateTime.now().toLocal();
      final inicioDia = DateTime(hoy.year, hoy.month, hoy.day).toUtc().toIso8601String();
      final finDia = DateTime(hoy.year, hoy.month, hoy.day).add(const Duration(days: 1)).toUtc().toIso8601String();

      final pagosHoy = await Supabase.instance.client
          .from('pagos')
          .select()
          .eq('prestamo_id', pId)
          .gte('fecha_pago', inicioDia)
          .lt('fecha_pago', finDia);

      if (pagosHoy.isEmpty) {
        _showSnack('No hay acciones registradas hoy para reimprimir.');
        return;
      }

      final pagosMora = pagosHoy.where((p) => (p['monto_mora'] ?? 0) > 0 && (p['monto_cuota_base'] ?? 0) == 0).toList();
      final pagosCuotas = pagosHoy.where((p) => (p['monto_cuota_base'] ?? 0) > 0).toList();
      final esLiquidado = _prestamo!['estado'] == 'liquidado';

      List<Map<String, dynamic>> opciones = [];

      if (pagosMora.isNotEmpty) {
        double totalMora = pagosMora.fold(0.0, (sum, p) => sum + (p['monto_mora'] ?? 0).toDouble());
        opciones.add({
          'titulo': 'Pago de Mora (\$${totalMora.toStringAsFixed(2)})',
          'accion': () => _imprimirTicket(montoPagado: totalMora, soloMora: true)
        });
      }

      if (pagosCuotas.isNotEmpty) {
        double totalCuotas = pagosCuotas.fold(0.0, (sum, p) => sum + ((p['monto_cuota_base'] ?? 0) + (p['monto_mora'] ?? 0)).toDouble());
        int numCuotas = pagosCuotas.length;
        if (esLiquidado) {
          opciones.add({
            'titulo': 'Liquidación (\$${totalCuotas.toStringAsFixed(2)})',
            'accion': () => _imprimirTicket(montoPagado: totalCuotas, cuotasQueSePagan: numCuotas, esLiquidacion: true)
          });
        } else {
          opciones.add({
            'titulo': numCuotas > 1 ? 'Adelanto de Cuotas (\$${totalCuotas.toStringAsFixed(2)})' : 'Cobro de Cuota (\$${totalCuotas.toStringAsFixed(2)})',
            'accion': () => _imprimirTicket(montoPagado: totalCuotas, cuotasQueSePagan: numCuotas)
          });
        }
      }

      if (opciones.isEmpty) {
        _showSnack('No hay acciones imprimibles hoy.');
        return;
      }

      if (opciones.length == 1) {
        _showSnack('Reimprimiendo ticket...');
        await opciones.first['accion']();
      } else {
        if (!mounted) return;
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Reimprimir Ticket', style: TextStyle(color: Color(0xFF09305A), fontWeight: FontWeight.bold)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: opciones.map((op) => ListTile(
                leading: const Icon(Icons.print, color: Colors.blue),
                title: Text(op['titulo']),
                onTap: () async {
                  Navigator.pop(ctx);
                  _showSnack('Reimprimiendo ticket...');
                  await op['accion']();
                },
              )).toList(),
            ),
          )
        );
      }

    } catch (e) {
      _showSnack('Error al reimprimir: $e', isError: true);
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _solicitarRenovacion(bool esAnticipada) async {
    final montoCtrl = TextEditingController();
    final result = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(esAnticipada ? 'Renovación Anticipada' : 'Renovar Crédito', style: const TextStyle(color: Color(0xFF09305A), fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Ingresa el monto que el cliente desea solicitar en el nuevo préstamo:'),
            const SizedBox(height: 16),
            TextField(
              controller: montoCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: 'Monto Solicitado',
                prefixText: '\$ ',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          ElevatedButton(
            onPressed: () {
               final m = double.tryParse(montoCtrl.text);
               if (m != null && m > 0) Navigator.pop(ctx, m);
            },
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF09305A), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
            child: const Text('Enviar Solicitud', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (result == null) return;

    setState(() => _isProcessing = true);
    try {
      final cobradorId = Supabase.instance.client.auth.currentUser!.id;
      
      await Supabase.instance.client.from('solicitudes_renovacion').insert({
        'prestamo_actual_id': _prestamo!['id'],
        'cliente_id': _prestamo!['cliente_id'],
        'cobrador_id': cobradorId,
        'monto_solicitado': result,
        'es_anticipada': esAnticipada,
      });

      _showSnack('Solicitud de renovación enviada al dueño.');
    } catch (e) {
      _showSnack('Error al enviar solicitud: $e', isError: true);
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _llamar() async {
    final t = widget.cliente['telefono'] ?? '';
    if (t.isEmpty) return;
    try { await launchUrl(Uri.parse('tel:$t')); } catch (_) {}
  }

  // â”€â”€ UI â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(backgroundColor: Color(0xFFF9FAFB), body: Center(child: CircularProgressIndicator(color: Color(0xFF09305A))));
    }
    final p = _prestamo!;
    final atrasosConteo = (p['cuotas_atrasadas_conteo'] ?? 0) as int;
    
    // Aumentar dias totales en base a las cuotas atrasadas (para mostrar el progreso corregido)
    final cuotasPagadas = _cuotas.where((c) => c['estado_pago'] == 'pagado').length;
    final totalCuotas = _cuotas.length;
    final progreso = totalCuotas == 0 ? 0.0 : cuotasPagadas / totalCuotas;
    
    final cuotaDiaria = (p['cuota_diaria'] ?? 0).toDouble();
    final faltante = (p['faltante_actual'] ?? 0).toDouble();
    final mora = (p['mora_acumulada'] ?? 0).toDouble();
    final penalizacion = (p['penalizacion_aplicada'] ?? 0).toDouble();
    final montoAtrasos = atrasosConteo * cuotaDiaria;
    final tieneMoraOAtraso = mora > 0 || atrasosConteo > 0;
    final idShort = widget.cliente['id'].toString().substring(0, 8).toUpperCase();

    return Scaffold(
      backgroundColor: const Color(0xFFF9FAFB),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF9FAFB),
        foregroundColor: const Color(0xFF09305A),
        elevation: 0,
        title: const Text('Atrás', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        titleSpacing: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context, _atendido ? _resultadoAccion : null),
        ),
        actions: [
          if (tieneMoraOAtraso && !_atendido)
            Container(
              margin: const EdgeInsets.only(right: 16, top: 12, bottom: 12),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(color: const Color(0xFFFEF3C7), borderRadius: BorderRadius.circular(8)),
              child: const Text('PRIORITARIO', style: TextStyle(color: Color(0xFFD97706), fontWeight: FontWeight.bold, fontSize: 12)),
            ),
          if (_atendido)
            IconButton(
              icon: const Icon(Icons.print_outlined),
              tooltip: 'Reimprimir ticket',
              onPressed: _isProcessing ? null : _reimprimirAccionesHoy,
            ),
        ],
      ),
      body: Stack(
        children: [
          ListView(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 160),
            children: [
              // BANNER: Modo consulta (fuera de ruta)
              if (!widget.enRuta)
                Container(
                  margin: const EdgeInsets.only(top: 12, bottom: 4),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF7CD),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFF59E0B)),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.visibility_outlined, color: Color(0xFFB45309), size: 20),
                      SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'MODO CONSULTA â€” Este cliente no está en tu ruta de hoy. No puedes realizar acciones.',
                          style: TextStyle(color: Color(0xFFB45309), fontWeight: FontWeight.bold, fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ),
              // Nombre
              Text(widget.cliente['nombre_completo'] ?? 'Sin nombre',
                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Color(0xFF09305A))),
              const SizedBox(height: 4),
              Row(children: [
                const Icon(Icons.verified_outlined, size: 16, color: Colors.blue),
                const SizedBox(width: 4),
                Text('#$idShort', style: const TextStyle(color: Colors.grey, fontSize: 13, fontWeight: FontWeight.bold)),
                const SizedBox(width: 8),
                Expanded(child: Text(widget.cliente['direccion'] ?? '', style: const TextStyle(color: Colors.grey, fontSize: 13), maxLines: 1, overflow: TextOverflow.ellipsis)),
              ]),
              const SizedBox(height: 20),

              // Tarjetas info
              Row(children: [
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.grey.shade200)),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Text('CRí‰DITO', style: TextStyle(fontSize: 11, color: Colors.grey, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 6),
                      Text('$cuotasPagadas / $totalCuotas', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF09305A))),
                      const SizedBox(height: 6),
                      ClipRRect(borderRadius: BorderRadius.circular(8),
                        child: LinearProgressIndicator(value: progreso, backgroundColor: Colors.grey.shade200, color: const Color(0xFF09305A), minHeight: 4)),
                      const SizedBox(height: 6),
                      const Text('Vence: Mañana', style: TextStyle(fontSize: 11, color: Colors.grey)),
                    ]),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.grey.shade200)),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Text('PERIODICIDAD', style: TextStyle(fontSize: 11, color: Colors.grey, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 6),
                      const Text('Cobro Diario', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF09305A))),
                      const SizedBox(height: 6),
                      const Text('Mantén la tasa preferencial.', style: TextStyle(fontSize: 11, color: Colors.grey)),
                    ]),
                  ),
                ),
              ]),
              const SizedBox(height: 16),

              // Tarjeta principal de cobro
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.grey.shade200)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('TOTAL A LIQUIDAR HOY', style: TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Text(formatter.format(cuotaDiaria), style: const TextStyle(fontSize: 36, fontWeight: FontWeight.bold, color: Color(0xFF09305A))),
                  const Divider(height: 32),
                  _rowInfo('Saldo Pendiente', formatter.format(faltante + mora)),
                  if (mora > 0 || atrasosConteo > 0) ...[
                    const SizedBox(height: 6),
                    Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                      const Text('  â”” Crédito:', style: TextStyle(color: Colors.grey, fontSize: 12)),
                      Text(formatter.format(faltante), style: const TextStyle(color: Colors.grey, fontSize: 12)),
                    ]),
                    if (mora > 0) Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                      const Text('  â”” Moratorios:', style: TextStyle(color: Color(0xFFDC2626), fontSize: 12)),
                      Text(formatter.format(mora), style: const TextStyle(color: Color(0xFFDC2626), fontSize: 12, fontWeight: FontWeight.bold)),
                    ]),
                    if (atrasosConteo > 0) Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                      Text('  â”” Cuota atrasada ($atrasosConteo):', style: const TextStyle(color: Color(0xFFDC2626), fontSize: 12)),
                      Text(formatter.format(montoAtrasos), style: const TextStyle(color: Color(0xFFDC2626), fontSize: 12, fontWeight: FontWeight.bold)),
                    ]),
                  ],
                  const SizedBox(height: 20),

                  // Botón adelantar
                  if (p['estado'] != 'liquidado' && faltante > 0)
                    InkWell(
                      onTap: (_isProcessing || !widget.enRuta) ? null : _adelantarPagos,
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        decoration: BoxDecoration(color: const Color(0xFFEFF6FF), borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFFBFDBFE))),
                        child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                          Icon(Icons.fast_forward_rounded, size: 18, color: Color(0xFF09305A)),
                          SizedBox(width: 8),
                          Text('Adelantar Pagos', style: TextStyle(color: Color(0xFF09305A), fontWeight: FontWeight.bold, fontSize: 15)),
                        ]),
                      ),
                    ),
                  
                  if (p['estado'] != 'liquidado' && faltante > 0)
                    const SizedBox(height: 12),

                  // Botón Liquidar
                  if (p['estado'] != 'liquidado' && faltante > 0)
                    InkWell(
                      onTap: (_isProcessing || !widget.enRuta) ? null : _liquidarCredito,
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        decoration: BoxDecoration(color: const Color(0xFFECFDF5), borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFFA7F3D0))),
                        child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                          Icon(Icons.check_circle_outline, size: 18, color: Color(0xFF065F46)),
                          SizedBox(width: 8),
                          Text('Liquidar Préstamo', style: TextStyle(color: Color(0xFF065F46), fontWeight: FontWeight.bold, fontSize: 15)),
                        ]),
                      ),
                    ),
                ]),
              ),
              const SizedBox(height: 16),

              if (cuotasPagadas >= 18 && p['estado'] != 'liquidado' && faltante > 0)
                const SizedBox(height: 12),

              // Botón Renovar (Anticipada)
                  if (cuotasPagadas >= 18 && p['estado'] != 'liquidado' && faltante > 0)
                    InkWell(
                      onTap: (_isProcessing || !widget.enRuta) ? null : () => _solicitarRenovacion(true),
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        decoration: BoxDecoration(color: const Color(0xFFFFFBEB), borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFFFDE68A))),
                        child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                          Icon(Icons.autorenew_rounded, size: 18, color: Color(0xFFB45309)),
                          SizedBox(width: 8),
                          Text('Renovar Crédito (Anticipado)', style: TextStyle(color: Color(0xFFB45309), fontWeight: FontWeight.bold, fontSize: 15)),
                        ]),
                      ),
                    ),

                  // Botón Renovar (Liquidado)
                  if (p['estado'] == 'liquidado' || faltante <= 0)
                    InkWell(
                      onTap: (_isProcessing || !widget.enRuta) ? null : () => _solicitarRenovacion(false),
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        decoration: BoxDecoration(color: const Color(0xFFFFFBEB), borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFFFDE68A))),
                        child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                          Icon(Icons.autorenew_rounded, size: 18, color: Color(0xFFB45309)),
                          SizedBox(width: 8),
                          Text('Renovar Crédito', style: TextStyle(color: Color(0xFFB45309), fontWeight: FontWeight.bold, fontSize: 15)),
                        ]),
                      ),
                    ),

              // Sección mora/atraso (solo si aplica)
              if (tieneMoraOAtraso) ...[
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(color: const Color(0xFFFFF1F2), borderRadius: BorderRadius.circular(16), border: Border.all(color: const Color(0xFFFECACA))),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      const Icon(Icons.warning_amber_rounded, color: Color(0xFFDC2626), size: 16),
                      const SizedBox(width: 6),
                      const Text('MORA PENDIENTE', style: TextStyle(color: Color(0xFFDC2626), fontWeight: FontWeight.bold, fontSize: 12)),
                    ]),
                    const SizedBox(height: 10),
                    Text('Total: ${formatter.format(mora)}',
                        style: const TextStyle(color: Color(0xFFDC2626), fontWeight: FontWeight.bold, fontSize: 24)),
                    const SizedBox(height: 4),
                    Text('Días acumulados: $atrasosConteo', style: const TextStyle(color: Color(0xFFEF4444), fontSize: 13)),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: (_isProcessing || !widget.enRuta) ? null : _pagarMoraAtraso,
                        icon: const Icon(Icons.credit_card, size: 18, color: Colors.white),
                        label: const Text('PAGAR MORA', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                        style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFDC2626), padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                      ),
                    ),
                  ]),
                ),
                const SizedBox(height: 16),
              ],

              // Botón Llamar
              InkWell(
                onTap: _llamar,
                borderRadius: BorderRadius.circular(14),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: Colors.grey.shade200)),
                  child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Icon(Icons.phone_outlined, size: 18, color: Color(0xFF09305A)),
                    SizedBox(width: 8),
                    Text('LLAMAR', style: TextStyle(color: Color(0xFF09305A), fontWeight: FontWeight.bold, fontSize: 15, letterSpacing: 1)),
                  ]),
                ),
              ),
            ],
          ),

          Positioned(
            left: 0, right: 0, bottom: 0,
            child: _atendido
              ? _buildBannerAtendido()
              : (_cuotaHoy() != null
                  ? Container(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 16, offset: const Offset(0, -4))],
                      ),
                      child: Row(children: [
                        Expanded(child: _accionBtn('NO PAGí“', Icons.cancel_outlined, const Color(0xFFFFF1F2), const Color(0xFFDC2626), (_isProcessing || !widget.enRuta) ? null : _noPago)),
                        const SizedBox(width: 8),
                        Expanded(child: _accionBtn('PASAR', Icons.schedule_outlined, const Color(0xFFFFFBEB), const Color(0xFFD97706), (_isProcessing || !widget.enRuta) ? null : _pasar)),
                        const SizedBox(width: 8),
                        Expanded(
                          flex: 2,
                          child: ElevatedButton.icon(
                            onPressed: (_isProcessing || !widget.enRuta) ? null : _cobrar,
                            icon: const Icon(Icons.check_circle_outline, size: 18, color: Colors.white),
                            label: const Text('COBRAR', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF09305A),
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                              elevation: 0,
                            ),
                          ),
                        ),
                      ]),
                    )
                  : Container(
                      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 16, offset: const Offset(0, -4))],
                      ),
                      child: const Text(
                        'No hay cuotas programadas para cobrar el día de hoy.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold, fontSize: 14),
                      ),
                    )),
          ),
          if (_isProcessing)
            Container(color: Colors.black26, child: const Center(child: CircularProgressIndicator(color: Color(0xFF09305A)))),
        ],
      ),
    );
  }

  Widget _buildBannerAtendido() {
    final esCobrado = _resultadoAccion == 'cobrado';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 36),
      decoration: BoxDecoration(
        color: esCobrado ? const Color(0xFFF0FDF4) : const Color(0xFFFFF7ED),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 16, offset: const Offset(0, -4))],
        border: Border(top: BorderSide(color: esCobrado ? const Color(0xFFBBF7D0) : const Color(0xFFFED7AA), width: 1.5)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: esCobrado ? const Color(0xFF22C55E) : const Color(0xFFF97316),
              shape: BoxShape.circle,
            ),
            child: Icon(
              esCobrado ? Icons.check_rounded : Icons.block_rounded,
              color: Colors.white,
              size: 22,
            ),
          ),
          const SizedBox(width: 14),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                esCobrado ? 'Â¡Cobro Registrado!' : 'Registrado como No Pagó',
                style: TextStyle(
                  color: esCobrado ? const Color(0xFF15803D) : const Color(0xFFC2410C),
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'Atendido el día de hoy',
                style: TextStyle(color: esCobrado ? const Color(0xFF166534) : const Color(0xFF9A3412), fontSize: 13),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _rowInfo(String label, String valor) {
    return Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
      Text(label, style: const TextStyle(color: Colors.grey, fontSize: 14)),
      Text(valor, style: const TextStyle(color: Color(0xFF09305A), fontWeight: FontWeight.bold, fontSize: 14)),
    ]);
  }

  Widget _accionBtn(String label, IconData icon, Color bg, Color fg, VoidCallback? onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(14)),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, color: fg, size: 18),
          const SizedBox(height: 4),
          Text(label, style: TextStyle(color: fg, fontWeight: FontWeight.bold, fontSize: 11)),
        ]),
      ),
    );
  }
}
