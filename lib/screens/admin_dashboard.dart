import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'clientes_tab.dart';
import 'cobradores_tab.dart';

import 'configuracion_tab.dart';
import 'admin_ruta_cobrador.dart';
import 'admin_notificaciones_screen.dart';

class AdminDashboard extends StatefulWidget {
  final Map<String, dynamic> perfil;

  const AdminDashboard({super.key, required this.perfil});

  @override
  State<AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminDashboard> {
  int _selectedIndex = 0;
  late List<Widget> _pages;

  @override
  void initState() {
    super.initState();
    _pages = [
      InicioTab(perfil: widget.perfil),
      const ClientesTab(),
      const CobradoresTab(),
      const ConfiguracionTab(),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF3F4F6),
      body: _pages[_selectedIndex],
      bottomNavigationBar: BottomNavigationBar(
        type: BottomNavigationBarType.fixed,
        currentIndex: _selectedIndex,
        selectedItemColor: const Color(0xFF09305A),
        unselectedItemColor: Colors.grey,
        selectedLabelStyle: const TextStyle(fontWeight: FontWeight.bold),
        onTap: (index) {
          setState(() {
            _selectedIndex = index;
          });
        },
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.home_outlined),
            activeIcon: Icon(Icons.home),
            label: 'Inicio',
          ),
          BottomNavigationBarItem(
             icon: Icon(Icons.people_outline),
             activeIcon: Icon(Icons.people),
            label: 'Clientes',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.work_outline),
            activeIcon: Icon(Icons.work),
            label: 'Cobradores',
          ),
          BottomNavigationBarItem(
             icon: Icon(Icons.settings_outlined),
             activeIcon: Icon(Icons.settings),
            label: 'Config',
          ),
        ],
      ),
    );
  }
}

class InicioTab extends StatefulWidget {
  final Map<String, dynamic> perfil;
  const InicioTab({super.key, required this.perfil});

  @override
  State<InicioTab> createState() => _InicioTabState();
}

class _InicioTabState extends State<InicioTab> {
  double _totalInvertido = 0;
  double _utilidadGenerada = 0;
  int _notifCount = 0;
  bool _isLoading = true;
  List<dynamic> _cobradores = [];

  @override
  void initState() {
    super.initState();
    _fetchDashboardData();
  }

  Future<void> _fetchDashboardData() async {
    try {
      final currentUserId = Supabase.instance.client.auth.currentUser?.id;
      if (currentUserId == null) return;

      final prestamosResponse = await Supabase.instance.client.from('prestamos').select('monto_principal');
      
      double totalInver = 0;
      for (var row in prestamosResponse) {
        totalInver += (row['monto_principal'] as num?)?.toDouble() ?? 0;
      }

      final pagosResponse = await Supabase.instance.client.from('pagos').select('monto_cuota_base');
      
      double utilGenerada = 0;
      for (var row in pagosResponse) {
        utilGenerada += (row['monto_cuota_base'] as num?)?.toDouble() ?? 0;
      }

      // -- FETCH COBRADORES DATA --
      final hoyLocal = DateTime.now().toLocal();
      final hoyStr = '${hoyLocal.year.toString().padLeft(4, '0')}-${hoyLocal.month.toString().padLeft(2, '0')}-${hoyLocal.day.toString().padLeft(2, '0')}';
      final inicioLocal = DateTime(hoyLocal.year, hoyLocal.month, hoyLocal.day);
      final finLocal = inicioLocal.add(const Duration(days: 1));

      final perfilesRes = await Supabase.instance.client
          .from('perfiles')
          .select('id, nombre_completo')
          .eq('rol', 'cobrador')
          .eq('activo', true);

      final pagosHoy = await Supabase.instance.client
          .from('pagos')
          .select('registrado_por, monto_recibido')
          .gte('fecha_pago', inicioLocal.toUtc().toIso8601String())
          .lt('fecha_pago', finLocal.toUtc().toIso8601String());

      final Map<String, double> recaudadoPorCobrador = {};
      final Map<String, double> moraRecaudadaPorCobrador = {};
      for (var pago in pagosHoy as List) {
        final id = pago['registrado_por'] as String?;
        if (id == null) continue;
        recaudadoPorCobrador[id] = (recaudadoPorCobrador[id] ?? 0) +
            ((pago['monto_recibido'] ?? 0) as num).toDouble();
        moraRecaudadaPorCobrador[id] = (moraRecaudadaPorCobrador[id] ?? 0) +
            ((pago['monto_mora'] ?? 0) as num).toDouble();
      }

      final cuotasHoy = await Supabase.instance.client
          .from('cuotas')
          .select('monto_cuota, prestamos!inner(cobrador_id, estado)')
          .eq('fecha_vencimiento', hoyStr)
          .neq('estado_pago', 'vencido')
          .eq('prestamos.estado', 'activo');

      final Map<String, double> metaPorCobrador = {};
      for (var cuota in cuotasHoy as List) {
        final prestamo = cuota['prestamos'];
        if (prestamo == null) continue;
        final id = prestamo['cobrador_id'] as String?;
        if (id == null) continue;
        metaPorCobrador[id] = (metaPorCobrador[id] ?? 0) +
            ((cuota['monto_cuota'] ?? 0) as num).toDouble();
      }

      final List<Map<String, dynamic>> cobradoresData = [];
      for (var perfil in perfilesRes as List) {
        final id = perfil['id'] as String;
        final recaudado = recaudadoPorCobrador[id] ?? 0.0;
        final moraAdicional = moraRecaudadaPorCobrador[id] ?? 0.0;
        final metaScheduled = (metaPorCobrador[id] ?? 0.0) + moraAdicional;
        final meta = recaudado > metaScheduled ? recaudado : metaScheduled;
        cobradoresData.add({
          'id': id,
          'nombre_completo': perfil['nombre_completo'],
          'recaudado_hoy': recaudado,
          'meta_total_hoy': meta,
        });
      }

      final notifRes = await Supabase.instance.client
          .from('solicitudes_renovacion')
          .select('id')
          .eq('estado', 'pendiente');

      if (mounted) {
        setState(() {
          _totalInvertido = totalInver;
          _utilidadGenerada = utilGenerada;
          _cobradores = cobradoresData;
          _notifCount = (notifRes as List).length;
          _isLoading = false;
        });
      }
    } catch (e) {
      print('Error fetching dashboard: $e');
      setState(() { _isLoading = false; });
    }
  }

  String _getInitial() {
    final nombre = widget.perfil['nombre_completo'] as String? ?? 'Usuario';
    return nombre.isNotEmpty ? nombre[0].toUpperCase() : 'U';
  }

  String _getFirstName() {
    final nombre = widget.perfil['nombre_completo'] as String? ?? 'Usuario';
    return nombre.split(' ')[0];
  }

  final formatter = NumberFormat.currency(locale: 'es_MX', symbol: '\$');

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          padding: EdgeInsets.only(
            top: MediaQuery.of(context).padding.top + 30,
            left: 24,
            right: 24,
            bottom: 30
          ),
          color: const Color(0xFF09305A),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Hola ${_getFirstName()}', style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold)),
                  Row(
                    children: [
                      Stack(
                        children: [
                          IconButton(
                            icon: const Icon(Icons.notifications_outlined, color: Colors.white, size: 28),
                            onPressed: () async {
                              await Navigator.push(context, MaterialPageRoute(builder: (_) => const AdminNotificacionesScreen()));
                              _fetchDashboardData();
                            },
                          ),
                          if (_notifCount > 0)
                            Positioned(
                              right: 8,
                              top: 8,
                              child: Container(
                                padding: const EdgeInsets.all(4),
                                decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
                                child: Text('$_notifCount', style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                              ),
                            )
                        ],
                      ),
                      const SizedBox(width: 8),
                      Container(
                        decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Colors.white24, width: 1)),
                        child: CircleAvatar(backgroundColor: const Color(0xFF163E6E), radius: 22, child: Text(_getInitial(), style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold))),
                      ),
                    ]
                  )
                ]
              ),
              const SizedBox(height: 40),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  const Text('TOTAL INVERTIDO (CAPITAL)', style: TextStyle(color: Colors.white70, fontSize: 12, letterSpacing: 1.2, fontWeight: FontWeight.w600)),
                  _isLoading ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.amber, strokeWidth: 2))
                  : Text(formatter.format(_totalInvertido), style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold))
                ]
              ),
              const SizedBox(height: 8),
              Container(height: 4, width: double.infinity, color: Colors.amber),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  const Text('UTILIDAD GENERADA', style: TextStyle(color: Colors.white70, fontSize: 12, letterSpacing: 1.2, fontWeight: FontWeight.w600)),
                  _isLoading ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.lightBlue, strokeWidth: 2))
                  : Text(formatter.format(_utilidadGenerada), style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold))
                ]
              ),
              const SizedBox(height: 8),
              Container(height: 4, width: double.infinity, color: Colors.lightBlue),
            ]
          )
        ),
        Expanded(
          child: Container(
            color: const Color(0xFFF9FAFB),
            width: double.infinity,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(24, 24, 24, 16),
                  child: Text('RUTAS DE COBRADORES', style: TextStyle(color: Colors.grey, fontSize: 14, letterSpacing: 1.2, fontWeight: FontWeight.w600)),
                ),
                Expanded(
                  child: _isLoading 
                    ? const Center(child: CircularProgressIndicator())
                    : _cobradores.isEmpty
                        ? Center(child: Text('No hay cobradores activos.', style: TextStyle(color: Colors.grey[400], fontSize: 16)))
                        : ListView.builder(
                            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                            itemCount: _cobradores.length,
                            itemBuilder: (context, index) {
                              final cobrador = _cobradores[index];
                              final double recaudado = (cobrador['recaudado_hoy'] ?? 0).toDouble();
                              final double meta = (cobrador['meta_total_hoy'] ?? 0).toDouble();
                              
                              double progreso = 0;
                              if (meta > 0) progreso = (recaudado / meta).clamp(0.0, 1.0);

                              return GestureDetector(
                                onTap: () {
                                  Navigator.push(context, MaterialPageRoute(
                                    builder: (_) => AdminRutaCobradorScreen(
                                      cobradorId: cobrador['id'],
                                      nombreCobrador: cobrador['nombre_completo'] ?? 'Sin Nombre',
                                    )
                                  ));
                                },
                                child: Container(
                                  margin: const EdgeInsets.only(bottom: 16),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(20),
                                    boxShadow: [
                                      BoxShadow(color: const Color(0xFF09305A).withOpacity(0.06), blurRadius: 16, offset: const Offset(0, 4)),
                                    ],
                                  ),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(20),
                                    child: Stack(
                                      children: [
                                        Positioned(left: 0, top: 0, bottom: 0, width: 6, child: Container(color: const Color(0xFF09305A))),
                                        Padding(
                                          padding: const EdgeInsets.all(20),
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Row(
                                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                                children: [
                                                  Text(cobrador['nombre_completo'] ?? 'Sin Nombre', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF09305A))),
                                                  const Icon(Icons.chevron_right, color: Colors.grey),
                                                ],
                                              ),
                                              const SizedBox(height: 16),
                                              Row(
                                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                                children: [
                                                  Column(
                                                    crossAxisAlignment: CrossAxisAlignment.start,
                                                    children: [
                                                      const Text('Recaudado', style: TextStyle(color: Colors.grey, fontSize: 12)),
                                                      Text(formatter.format(recaudado), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF09305A))),
                                                    ],
                                                  ),
                                                  Column(
                                                    crossAxisAlignment: CrossAxisAlignment.end,
                                                    children: [
                                                      const Text('Meta Hoy', style: TextStyle(color: Colors.grey, fontSize: 12)),
                                                      Text(formatter.format(meta), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.black87)),
                                                    ],
                                                  ),
                                                ],
                                              ),
                                              const SizedBox(height: 12),
                                              ClipRRect(
                                                borderRadius: BorderRadius.circular(10),
                                                child: LinearProgressIndicator(
                                                  value: progreso,
                                                  backgroundColor: Colors.grey.shade200,
                                                  color: const Color(0xFF06B6D4),
                                                  minHeight: 6,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                ),
              ],
            ),
          ),
        ),
      ]
    );
  }
}
