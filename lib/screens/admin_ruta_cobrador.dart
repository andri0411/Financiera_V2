import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'cliente_detalle_screen.dart';

class AdminRutaCobradorScreen extends StatefulWidget {
  final String cobradorId;
  final String nombreCobrador;

  const AdminRutaCobradorScreen({
    super.key,
    required this.cobradorId,
    required this.nombreCobrador,
  });

  @override
  State<AdminRutaCobradorScreen> createState() => _AdminRutaCobradorScreenState();
}

class _AdminRutaCobradorScreenState extends State<AdminRutaCobradorScreen> {
  final formatter = NumberFormat.currency(locale: 'es_MX', symbol: '\$');
  bool _isLoading = true;
  List<Map<String, dynamic>> _clientesPrestamos = [];

  @override
  void initState() {
    super.initState();
    _fetchClientes();
  }

  Future<void> _fetchClientes() async {
    setState(() => _isLoading = true);
    try {
      // Cargar todos los préstamos activos asignados a este cobrador
      final prestamos = await Supabase.instance.client
          .from('prestamos')
          .select('*, clientes(*)')
          .eq('cobrador_id', widget.cobradorId)
          .eq('estado', 'activo');

      List<Map<String, dynamic>> datos = [];
      for (var p in prestamos as List) {
        if (p['clientes'] != null) {
          datos.add({
            'cliente': p['clientes'],
            'monto_principal': p['monto_principal'] ?? 0,
          });
        }
      }

      setState(() {
        _clientesPrestamos = datos;
        _isLoading = false;
      });
    } catch (e) {
      print('Error al cargar la ruta del cobrador: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF9FAFB),
      appBar: AppBar(
        title: Text(
          'Ruta de ${widget.nombreCobrador}',
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        backgroundColor: const Color(0xFF09305A),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF09305A)))
          : _clientesPrestamos.isEmpty
              ? const Center(
                  child: Text(
                    'Este cobrador no tiene clientes activos asignados.',
                    style: TextStyle(color: Colors.grey, fontSize: 16),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(24),
                  itemCount: _clientesPrestamos.length,
                  itemBuilder: (context, index) {
                    final item = _clientesPrestamos[index];
                    final cliente = item['cliente'];
                    final double capitalPrestado = (item['monto_principal'] as num).toDouble();

                    return Card(
                      color: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: const BorderSide(color: Color(0xFFE5E7EB)),
                      ),
                      margin: const EdgeInsets.only(bottom: 16),
                      child: ListTile(
                        contentPadding: const EdgeInsets.all(16),
                        title: Text(
                          '${index + 1}. ${cliente['nombre_completo']}',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            color: Color(0xFF09305A),
                          ),
                        ),
                        subtitle: Padding(
                          padding: const EdgeInsets.only(top: 8.0),
                          child: Text(
                            'Capital prestado: ${formatter.format(capitalPrestado)}',
                            style: const TextStyle(
                              color: Colors.grey,
                            ),
                          ),
                        ),
                        trailing: const Icon(Icons.chevron_right, color: Colors.grey),
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => ClienteDetalleScreen(cliente: cliente),
                            ),
                          ).then((_) => _fetchClientes());
                        },
                      ),
                    );
                  },
                ),
    );
  }
}
