import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'admin_renovacion_detalle_screen.dart';

class AdminNotificacionesScreen extends StatefulWidget {
  const AdminNotificacionesScreen({super.key});

  @override
  State<AdminNotificacionesScreen> createState() => _AdminNotificacionesScreenState();
}

class _AdminNotificacionesScreenState extends State<AdminNotificacionesScreen> {
  bool _isLoading = true;
  List<Map<String, dynamic>> _solicitudes = [];
  final formatter = NumberFormat.currency(locale: 'es_MX', symbol: '\$');

  @override
  void initState() {
    super.initState();
    _fetchSolicitudes();
  }

  Future<void> _fetchSolicitudes() async {
    setState(() => _isLoading = true);
    try {
      final data = await Supabase.instance.client
          .from('solicitudes_renovacion')
          .select('''
            *,
            cliente:clientes(nombre_completo),
            cobrador:perfiles(nombre_completo)
          ''')
          .eq('estado', 'pendiente')
          .order('created_at', ascending: false);

      if (mounted) {
        setState(() {
          _solicitudes = List<Map<String, dynamic>>.from(data);
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

  void _abrirDetalle(Map<String, dynamic> solicitud) async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => AdminRenovacionDetalleScreen(solicitud: solicitud)),
    );
    if (result == true) {
      _fetchSolicitudes();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF9FAFB),
      appBar: AppBar(
        title: const Text('Solicitudes de Renovación', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFF09305A),
        foregroundColor: Colors.white,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF09305A)))
          : _solicitudes.isEmpty
              ? const Center(child: Text('No hay notificaciones pendientes.', style: TextStyle(color: Colors.grey, fontSize: 16)))
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _solicitudes.length,
                  itemBuilder: (context, index) {
                    final sol = _solicitudes[index];
                    final clienteNombre = sol['cliente']?['nombre_completo'] ?? 'Cliente Desconocido';
                    final cobradorNombre = sol['cobrador']?['nombre_completo'] ?? 'Cobrador Desconocido';
                    final montoSolicitado = (sol['monto_solicitado'] ?? 0).toDouble();
                    final esAnticipada = sol['es_anticipada'] == true;

                    return Card(
                      elevation: 2,
                      margin: const EdgeInsets.only(bottom: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      child: InkWell(
                        onTap: () => _abrirDetalle(sol),
                        borderRadius: BorderRadius.circular(16),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: esAnticipada ? const Color(0xFFFFFBEB) : const Color(0xFFEFF6FF),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Icon(
                                  esAnticipada ? Icons.warning_rounded : Icons.autorenew_rounded,
                                  color: esAnticipada ? const Color(0xFFB45309) : const Color(0xFF09305A),
                                  size: 28,
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(clienteNombre, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF09305A))),
                                    const SizedBox(height: 4),
                                    Text('Monto Solicitado: ${formatter.format(montoSolicitado)}', style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF059669))),
                                    const SizedBox(height: 2),
                                    Text('Cobrador: $cobradorNombre', style: const TextStyle(color: Colors.grey, fontSize: 12)),
                                  ],
                                ),
                              ),
                              const Icon(Icons.chevron_right, color: Colors.grey),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}
