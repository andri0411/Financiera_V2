// ignore_for_file: use_build_context_synchronously
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

class CobradorClienteDetalleScreen extends StatefulWidget {
  final Map<String, dynamic> cliente;
  final Map<String, dynamic> prestamo;

  const CobradorClienteDetalleScreen({
    super.key,
    required this.cliente,
    required this.prestamo,
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

  @override
  void initState() {
    super.initState();
    _prestamo = Map.from(widget.prestamo);
    _fetchData();
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

  // ── Helpers ──────────────────────────────────────────────

  Map<String, dynamic>? _cuotaHoy() {
    final hoy = DateTime.now();
    final hoyDate = DateTime(hoy.year, hoy.month, hoy.day);
    for (var c in _cuotas) {
      if (c['estado_pago'] == 'pendiente') {
        final fechaStr = c['fecha_vencimiento'];
        if (fechaStr != null) {
          final fecha = DateTime.tryParse(fechaStr);
          if (fecha != null && (fecha.isBefore(hoyDate) || fecha.isAtSameMomentAs(hoyDate))) {
            return c;
          }
        }
      }
    }
    return null;
  }

  bool _tieneAdelantos() {
    final pagadas = _cuotas.where((c) => c['estado_pago'] == 'pagado').length;
    final inicio = DateTime.tryParse(_prestamo?['fecha_inicio'] ?? '');
    if (inicio == null) return false;
    final diasTranscurridos = DateTime.now().difference(inicio).inDays;
    return pagadas > diasTranscurridos;
  }

  void _showSnack(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: isError ? Colors.red : const Color(0xFF22C55E),
      behavior: SnackBarBehavior.floating,
    ));
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

  // ── Acciones ─────────────────────────────────────────────

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
      if (mounted) setState(() { _atendido = true; _resultadoAccion = 'no_pago'; });
    } catch (e) {
      _showSnack('Error: \$e', isError: true);
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
    final cuotaDiaria = (_prestamo?['cuota_diaria'] ?? 0).toDouble();
    final atrasos = (_prestamo?['cuotas_atrasadas_conteo'] ?? 0) * cuotaDiaria;
    final total = mora + atrasos;
    final cuota = _cuotas.where((c) => c['estado_pago'] == 'pendiente').isNotEmpty
        ? _cuotas.firstWhere((c) => c['estado_pago'] == 'pendiente')
        : null;
    if (cuota == null) { _showSnack('No hay cuota pendiente.', isError: true); return; }
    final ok = await _confirm(
      'Pagar Mora / Atraso',
      'Se cobrará ${formatter.format(total)} (Atraso: ${formatter.format(atrasos)} + Mora: ${formatter.format(mora)}). ¿Confirmar?',
      confirmColor: const Color(0xFFDC2626),
    );
    if (!ok) return;
    setState(() => _isProcessing = true);
    try {
      final cobradorId = Supabase.instance.client.auth.currentUser!.id;
      await Supabase.instance.client.rpc('fn_procesar_pago', params: {
        'p_prestamo_id': _prestamo!['id'],
        'p_cuota_id': cuota['id'],
        'p_monto_total': total,
        'p_monto_base': atrasos,
        'p_monto_mora': mora,
        'p_monto_penalizacion': 0,
        'p_cobrador_id': cobradorId,
      });
      _showSnack('Mora y atraso pagados.');
      await _fetchData();
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

    // Solo se adelantan cuotas FUTURAS (fecha_vencimiento >= hoy)
    // Las cuotas atrasadas se aplazó la fecha de finalización del crédito
    final hoy = DateTime.now();
    final hoyDate = DateTime(hoy.year, hoy.month, hoy.day);
    final cuotasFuturas = _cuotas.where((c) {
      if (c['estado_pago'] != 'pendiente') return false;
      final fecha = DateTime.tryParse(c['fecha_vencimiento'] ?? '');
      if (fecha == null) return false;
      return !fecha.isBefore(hoyDate); // fecha >= hoy
    }).toList();

    if (cuotasFuturas.isEmpty) {
      _showSnack('No hay cuotas futuras para adelantar.', isError: true);
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
                          'Este cliente tiene $atrasosConteo cuota(s) atrasada(s). Los adelantos solo cubren cuotas futuras. Las cuotas atrasadas extienden la fecha de finalización del crédito.',
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
      _showSnack('$cuotasNum cuota(s) adelantada(s) exitosamente.');
      await _fetchData();
    } catch (e) {
      _showSnack('Error: $e', isError: true);
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _llamar() async {
    final t = widget.cliente['telefono'] ?? '';
    if (t.isEmpty) return;
    try { await launchUrl(Uri.parse('tel:$t')); } catch (_) {}
  }

  // ── UI ───────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(backgroundColor: Color(0xFFF9FAFB), body: Center(child: CircularProgressIndicator(color: Color(0xFF09305A))));
    }
    final p = _prestamo!;
    final cuotasPagadas = _cuotas.where((c) => c['estado_pago'] == 'pagado').length;
    final totalCuotas = _cuotas.length;
    final progreso = totalCuotas == 0 ? 0.0 : cuotasPagadas / totalCuotas;
    final cuotaDiaria = (p['cuota_diaria'] ?? 0).toDouble();
    final faltante = (p['faltante_actual'] ?? 0).toDouble();
    final mora = (p['mora_acumulada'] ?? 0).toDouble();
    final penalizacion = (p['penalizacion_aplicada'] ?? 0).toDouble();
    final atrasosConteo = (p['cuotas_atrasadas_conteo'] ?? 0) as int;
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
        ],
      ),
      body: Stack(
        children: [
          ListView(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 160),
            children: [
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
                      const Text('CRÉDITO', style: TextStyle(fontSize: 11, color: Colors.grey, fontWeight: FontWeight.bold)),
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
                  _rowInfo('Saldo Pendiente', formatter.format(faltante + montoAtrasos + mora)),
                  if (atrasosConteo > 0 || mora > 0) ...[
                    const SizedBox(height: 6),
                    Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                      const Text('  └ Crédito:', style: TextStyle(color: Colors.grey, fontSize: 12)),
                      Text(formatter.format(faltante), style: const TextStyle(color: Colors.grey, fontSize: 12)),
                    ]),
                    if (atrasosConteo > 0) Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                      Text('  └ Atrasos ($atrasosConteo días):', style: const TextStyle(color: Color(0xFFDC2626), fontSize: 12)),
                      Text(formatter.format(montoAtrasos), style: const TextStyle(color: Color(0xFFDC2626), fontSize: 12, fontWeight: FontWeight.bold)),
                    ]),
                    if (mora > 0) Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                      const Text('  └ Moratorios:', style: TextStyle(color: Color(0xFFDC2626), fontSize: 12)),
                      Text(formatter.format(mora), style: const TextStyle(color: Color(0xFFDC2626), fontSize: 12, fontWeight: FontWeight.bold)),
                    ]),
                  ],
                  const SizedBox(height: 10),
                  _rowInfo('Penalización Grave', formatter.format(penalizacion)),
                  const SizedBox(height: 20),
                  // Botón adelantar
                  InkWell(
                    onTap: _isProcessing ? null : _adelantarPagos,
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
                ]),
              ),
              const SizedBox(height: 16),

              // Sección mora/atraso (solo si aplica)
              if (tieneMoraOAtraso) ...[
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(color: const Color(0xFFFFF1F2), borderRadius: BorderRadius.circular(16), border: Border.all(color: const Color(0xFFFECACA))),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      const Icon(Icons.warning_amber_rounded, color: Color(0xFFDC2626), size: 16),
                      const SizedBox(width: 6),
                      const Text('MORA / ATRASO PENDIENTE', style: TextStyle(color: Color(0xFFDC2626), fontWeight: FontWeight.bold, fontSize: 12)),
                    ]),
                    const SizedBox(height: 10),
                    if (atrasosConteo > 0)
                      Text('Atrasos: ${formatter.format(montoAtrasos)} ($atrasosConteo día(s))',
                          style: const TextStyle(color: Color(0xFFDC2626), fontWeight: FontWeight.bold, fontSize: 16)),
                    if (mora > 0) ...[
                      const SizedBox(height: 4),
                      Text('Mora: ${formatter.format(mora)}', style: const TextStyle(color: Color(0xFFDC2626), fontWeight: FontWeight.bold, fontSize: 16)),
                    ],
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _isProcessing ? null : _pagarMoraAtraso,
                        icon: const Icon(Icons.credit_card, size: 18, color: Colors.white),
                        label: const Text('PAGAR MORA / ATRASO', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
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
                        Expanded(child: _accionBtn('NO PAGÓ', Icons.cancel_outlined, const Color(0xFFFFF1F2), const Color(0xFFDC2626), _isProcessing ? null : _noPago)),
                        const SizedBox(width: 8),
                        Expanded(child: _accionBtn('PASAR', Icons.schedule_outlined, const Color(0xFFFFFBEB), const Color(0xFFD97706), _isProcessing ? null : _pasar)),
                        const SizedBox(width: 8),
                        Expanded(
                          flex: 2,
                          child: ElevatedButton.icon(
                            onPressed: _isProcessing ? null : _cobrar,
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
                esCobrado ? '¡Cobro Registrado!' : 'Registrado como No Pagó',
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
