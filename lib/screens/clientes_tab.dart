import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'agregar_cliente.dart';
import 'cliente_detalle_screen.dart';

class ClientesTab extends StatefulWidget {
  const ClientesTab({super.key});

  @override
  State<ClientesTab> createState() => _ClientesTabState();
}

class _ClientesTabState extends State<ClientesTab> {
  final formatter = NumberFormat.currency(locale: 'es_MX', symbol: '\$');
  bool _isLoading = true;
  List<dynamic> _clientes = [];
  List<dynamic> _filteredClientes = [];
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _fetchClientes();
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _fetchClientes() async {
    try {
      // Consulta todos los clientes y trae su prestamo principal (activo)
      final response = await Supabase.instance.client
          .from('clientes')
          .select('*, prestamos(monto_principal, estado)')
          .order('created_at', ascending: false);
      
      setState(() {
        _clientes = response;
        _filteredClientes = response;
        _isLoading = false;
      });
    } catch (e) {
      print('Error al obtener clientes: $e');
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _onSearchChanged() {
    final query = _searchController.text.toLowerCase();
    setState(() {
      _filteredClientes = _clientes.where((cliente) {
        final nombre = (cliente['nombre_completo'] ?? '').toString().toLowerCase();
        return nombre.contains(query);
      }).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Header azul de la pestaña (Sin flex box, ocupa hasta arriba por padding de AdminDashboard)
        Container(
          width: double.infinity,
          padding: EdgeInsets.only(
            top: MediaQuery.of(context).padding.top + 20,
            left: 24,
            right: 24,
            bottom: 20,
          ),
          color: const Color(0xFF09305A),
          child: const Text(
            'Clientes',
            style: TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        
        // Contenido Blanco
        Expanded(
          child: Container(
            color: Colors.white,
            child: Stack(
              children: [
                Column(
                  children: [
                    // Buscador
                    Padding(
                      padding: const EdgeInsets.all(24.0),
                      child: Container(
                        decoration: BoxDecoration(
                          color: const Color(0xFFF3F4F6),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: TextField(
                          controller: _searchController,
                          decoration: const InputDecoration(
                            hintText: 'Buscar cliente...',
                            prefixIcon: Icon(Icons.search, color: Colors.grey),
                            border: InputBorder.none,
                            contentPadding: EdgeInsets.symmetric(vertical: 16),
                          ),
                        ),
                      ),
                    ),
                    
                    // Lista de clientes
                    Expanded(
                      child: _isLoading
                          ? const Center(child: CircularProgressIndicator())
                          : _filteredClientes.isEmpty
                              ? const Center(child: Text('No hay clientes.'))
                              : ListView.builder(
                                  padding: const EdgeInsets.symmetric(horizontal: 24.0),
                                  itemCount: _filteredClientes.length,
                                  itemBuilder: (context, index) {
                                    final cliente = _filteredClientes[index];
                                    final prestamos = cliente['prestamos'] as List<dynamic>? ?? [];
                                    
                                    // Obtenemos el prestamo activo si lo tiene para sumar el capital prestado
                                    double capitalPrestado = 0.0;
                                    for (var p in prestamos) {
                                      if (p['estado'] == 'activo') {
                                        capitalPrestado += (p['monto_principal'] as num?)?.toDouble() ?? 0.0;
                                      }
                                    }

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
                                              builder: (context) => ClienteDetalleScreen(cliente: cliente),
                                            ),
                                          );
                                        },
                                      ),
                                    );
                                  },
                                ),
                    ),
                  ],
                ),
                
                // Botón flotante para agregar cliente
                Positioned(
                  bottom: 24,
                  right: 24,
                  child: FloatingActionButton(
                    backgroundColor: const Color(0xFF09305A),
                    foregroundColor: Colors.white,
                    onPressed: () async {
                      final result = await Navigator.push(
                        context,
                        MaterialPageRoute(builder: (context) => const AgregarClienteScreen()),
                      );
                      if (result == true) {
                        _fetchClientes();
                      }
                    },
                    child: const Icon(Icons.add),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
