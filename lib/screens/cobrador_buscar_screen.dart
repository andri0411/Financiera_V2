import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'cobrador_cliente_detalle.dart';

class CobradorBuscarScreen extends StatefulWidget {
  const CobradorBuscarScreen({super.key});

  @override
  State<CobradorBuscarScreen> createState() => _CobradorBuscarScreenState();
}

class _CobradorBuscarScreenState extends State<CobradorBuscarScreen> {
  final formatter = NumberFormat.currency(locale: 'es_MX', symbol: '\$');
  final TextEditingController _searchController = TextEditingController();
  
  bool _isLoading = true;
  List<Map<String, dynamic>> _todosLosClientes = [];
  List<Map<String, dynamic>> _clientesFiltrados = [];

  @override
  void initState() {
    super.initState();
    _fetchClientes();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _fetchClientes() async {
    setState(() => _isLoading = true);
    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId == null) throw Exception('No hay usuario autenticado');

      // Obtener todos los préstamos asignados al cobrador (activos o liquidados/renovados)
      final prestamosActivos = await Supabase.instance.client
          .from('prestamos')
          .select('*, clientes(*)')
          .eq('cobrador_id', userId)
          .order('created_at', ascending: false);

      Set<String> clientesAgregados = {};
      List<Map<String, dynamic>> clientesTemp = [];
      for (var prestamo in prestamosActivos) {
        final cliente = prestamo['clientes'];
        if (cliente != null) {
          final clienteId = cliente['id'] as String;
          if (!clientesAgregados.contains(clienteId)) {
            clientesAgregados.add(clienteId);
            // Según lo solicitado, mostramos de "PENDIENTE" el monto principal (lo prestado sin interés)
            double montoPendiente = (prestamo['monto_principal'] ?? 0).toDouble();
            
            clientesTemp.add({
              'cliente': cliente,
              'prestamo': prestamo,
              'monto_pendiente': montoPendiente,
            });
          }
        }
      }

      _todosLosClientes = clientesTemp;
      _clientesFiltrados = clientesTemp;

    } catch (e) {
      print('Error al obtener clientes: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _filtrarClientes(String query) {
    if (query.isEmpty) {
      setState(() {
        _clientesFiltrados = _todosLosClientes;
      });
      return;
    }

    query = query.toLowerCase();
    setState(() {
      _clientesFiltrados = _todosLosClientes.where((item) {
        final cliente = item['cliente'];
        final nombre = (cliente['nombre_completo'] ?? '').toString().toLowerCase();
        final telefono = (cliente['telefono'] ?? '').toString().toLowerCase();
        
        return nombre.contains(query) || telefono.contains(query);
      }).toList();
    });
  }

  Future<void> _abrirMapa(Map<String, dynamic> cliente) async {
    final lat = cliente['latitud'];
    final lng = cliente['longitud'];

    if (lat != null && lng != null) {
      final Uri url = Uri.parse("https://www.google.com/maps/dir/?api=1&destination=$lat,$lng");
      try {
        await launchUrl(url, mode: LaunchMode.externalApplication);
        return;
      } catch (e) {
        print("Error abriendo mapa: $e");
      }
    }

    final d = cliente['direccion'];
    if (d != null && d.toString().trim().isNotEmpty) {
      final Uri url = Uri.parse("https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent(d)}");
      try {
        await launchUrl(url, mode: LaunchMode.externalApplication);
        return;
      } catch (e) {
        print("Error abriendo mapa con dirección: $e");
      }
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ubicación no disponible para este cliente')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF9FAFB),
      appBar: AppBar(
        backgroundColor: const Color(0xFF09305A),
        foregroundColor: Colors.white,
        title: const Text(
          'Buscar Cliente',
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 20),
        ),
        elevation: 0,
        centerTitle: false,
      ),
      body: Column(
        children: [
          // Barra de búsqueda flotante
          Container(
            color: Colors.white,
            padding: const EdgeInsets.all(16),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFF09305A)),
              ),
              child: TextField(
                controller: _searchController,
                onChanged: _filtrarClientes,
                decoration: const InputDecoration(
                  hintText: 'Nombre o teléfono...',
                  hintStyle: TextStyle(color: Colors.grey),
                  prefixIcon: Icon(Icons.phone_outlined, color: Colors.grey),
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                ),
              ),
            ),
          ),
          
          // Lista de resultados
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator(color: Color(0xFF09305A)))
                : _clientesFiltrados.isEmpty
                    ? const Center(
                        child: Text(
                          'No se encontraron clientes',
                          style: TextStyle(color: Colors.grey, fontSize: 16),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: _clientesFiltrados.length,
                        itemBuilder: (context, index) {
                          final item = _clientesFiltrados[index];
                          return _buildClienteCard(index + 1, item);
                        },
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildClienteCard(int numero, Map<String, dynamic> item) {
    final cliente = item['cliente'] as Map<String, dynamic>;
    final montoPendiente = item['monto_pendiente'] as double;
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () async {
            await Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => CobradorClienteDetalleScreen(
                  cliente: cliente,
                  prestamo: item['prestamo'],
                ),
              ),
            );
            _fetchClientes(); // Refrescar si hubo cambios
          },
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '$numero. ${cliente['nombre_completo'] ?? 'Sin nombre'}',
                        style: const TextStyle(
                          color: Color(0xFF09305A),
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'PENDIENTE',
                        style: TextStyle(
                          color: Colors.grey,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.0,
                        ),
                      ),
                      Text(
                        formatter.format(montoPendiente),
                        style: const TextStyle(
                          color: Color(0xFF09305A),
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
                InkWell(
                  onTap: () => _abrirMapa(cliente),
                  borderRadius: BorderRadius.circular(24),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE0F2FE),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.map_outlined,
                      color: Color(0xFF09305A),
                      size: 24,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
