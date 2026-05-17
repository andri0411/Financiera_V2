import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';

class AdminRenovacionDetalleScreen extends StatefulWidget {
  final Map<String, dynamic> solicitud;
  const AdminRenovacionDetalleScreen({super.key, required this.solicitud});

  @override
  State<AdminRenovacionDetalleScreen> createState() => _AdminRenovacionDetalleScreenState();
}

class _AdminRenovacionDetalleScreenState extends State<AdminRenovacionDetalleScreen> {
  bool _isLoading = true;
  bool _isProcessing = false;
  Map<String, dynamic>? _prestamoAntiguo;
  Map<String, dynamic>? _configuracion;
  
  final formatter = NumberFormat.currency(locale: 'es_MX', symbol: '\$');

  @override
  void initState() {
    super.initState();
    _fetchData();
  }

  Future<void> _fetchData() async {
    setState(() => _isLoading = true);
    try {
      final prestamoId = widget.solicitud['prestamo_actual_id'];
      
      final resP = await Supabase.instance.client
          .from('prestamos')
          .select()
          .eq('id', prestamoId)
          .single();
          
      final resC = await Supabase.instance.client
          .from('configuracion')
          .select()
          .eq('id', 1)
          .single();

      if (mounted) {
        setState(() {
          _prestamoAntiguo = resP;
          _configuracion = resC;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  Future<void> _rechazar() async {
    setState(() => _isProcessing = true);
    try {
      await Supabase.instance.client.rpc('fn_rechazar_renovacion', params: {
        'p_solicitud_id': widget.solicitud['id'],
      });
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
      setState(() => _isProcessing = false);
    }
  }

  Future<void> _aprobar(double nuevoPrincipal, double totalAPagar, double cuotaDiaria, int plazoDias) async {
    setState(() => _isProcessing = true);
    try {
      final res = await Supabase.instance.client.rpc('fn_aprobar_renovacion', params: {
        'p_solicitud_id': widget.solicitud['id'],
        'p_nuevo_monto_principal': nuevoPrincipal,
        'p_monto_total_pagar': totalAPagar,
        'p_cuota_diaria': cuotaDiaria,
        'p_plazo_dias': plazoDias,
      });
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
      setState(() => _isProcessing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading || _prestamoAntiguo == null || _configuracion == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final p = _prestamoAntiguo!;
    final c = _configuracion!;
    
    final montoSolicitado = (widget.solicitud['monto_solicitado'] ?? 0).toDouble();
    final faltanteAnterior = (p['faltante_actual'] ?? 0).toDouble();
    
    // Matemática del Nuevo Préstamo
    final tasaInteres = (c['tasa_interes_base'] ?? 25).toDouble() / 100.0;
    final pctCuotaDiaria = (c['porcentaje_cuota_diaria'] ?? 5).toDouble() / 100.0;
    
    final interesNuevo = montoSolicitado * tasaInteres;
    final totalAPagarNuevo = montoSolicitado + interesNuevo;
    final cuotaDiariaNueva = montoSolicitado * pctCuotaDiaria;
    final plazoDiasNuevo = cuotaDiariaNueva > 0 ? (totalAPagarNuevo / cuotaDiariaNueva).ceil() : 0;

    // Efectivo a entregar al cliente
    final aEntregar = montoSolicitado - faltanteAnterior;

    return Scaffold(
      backgroundColor: const Color(0xFFF9FAFB),
      appBar: AppBar(
        title: const Text('Detalle de Renovación'),
        backgroundColor: const Color(0xFF09305A),
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.grey.shade200)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('DATOS DEL NUEVO CRÉDITO', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold, fontSize: 12)),
                  const SizedBox(height: 16),
                  
                  _rowInfo('Nuevo Monto Solicitado', formatter.format(montoSolicitado), isBold: true, color: const Color(0xFF09305A)),
                  const SizedBox(height: 8),
                  _rowInfo('Deuda Anterior (Faltante)', '- ${formatter.format(faltanteAnterior)}', color: const Color(0xFFDC2626)),
                  const Divider(height: 24),
                  _rowInfo('Efectivo a Entregar al Cliente', formatter.format(aEntregar), isBold: true, color: const Color(0xFF059669)),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.grey.shade200)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('PLAN DE PAGOS (SIMULACIÓN)', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold, fontSize: 12)),
                  const SizedBox(height: 16),
                  
                  _rowInfo('Capital (Nuevo Monto)', formatter.format(montoSolicitado)),
                  const SizedBox(height: 8),
                  _rowInfo('Intereses (+${c["tasa_interes_base"]}%)', formatter.format(interesNuevo)),
                  const Divider(height: 24),
                  _rowInfo('Total a Pagar', formatter.format(totalAPagarNuevo), isBold: true, color: const Color(0xFF09305A)),
                  const SizedBox(height: 12),
                  _rowInfo('Cuota Diaria', formatter.format(cuotaDiariaNueva), isBold: true, color: const Color(0xFFD97706)),
                  const SizedBox(height: 8),
                  _rowInfo('Plazo', '$plazoDiasNuevo días'),
                ],
              ),
            ),
            
            const SizedBox(height: 32),
            if (aEntregar < 0)
              Container(
                padding: const EdgeInsets.all(12),
                margin: const EdgeInsets.only(bottom: 24),
                decoration: BoxDecoration(color: const Color(0xFFFEF2F2), borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFFFECACA))),
                child: const Row(
                  children: [
                    Icon(Icons.error_outline, color: Color(0xFFDC2626)),
                    SizedBox(width: 8),
                    Expanded(child: Text('El monto solicitado es menor que la deuda actual. El cliente terminaría debiendo dinero en vez de recibir efectivo.', style: TextStyle(color: Color(0xFFDC2626), fontSize: 13))),
                  ],
                ),
              ),

            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _isProcessing ? null : _rechazar,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFFDC2626), side: const BorderSide(color: Color(0xFFDC2626)),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))
                    ),
                    child: const Text('Rechazar', style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: ElevatedButton(
                    onPressed: (_isProcessing || aEntregar < 0) ? null : () => _aprobar(montoSolicitado, totalAPagarNuevo, cuotaDiariaNueva, plazoDiasNuevo),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF059669),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))
                    ),
                    child: const Text('Aprobar Renovación', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
                  ),
                ),
              ],
            )
          ],
        ),
      ),
    );
  }

  Widget _rowInfo(String label, String value, {bool isBold = false, Color? color}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: TextStyle(color: Colors.grey.shade700)),
        Text(value, style: TextStyle(fontWeight: isBold ? FontWeight.bold : FontWeight.normal, fontSize: isBold ? 16 : 14, color: color ?? Colors.black87)),
      ],
    );
  }
}
