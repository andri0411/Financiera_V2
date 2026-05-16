import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'clientes_tab.dart';
import 'cobradores_tab.dart';

import 'configuracion_tab.dart';

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
  bool _isLoading = true;

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

      setState(() {
        _totalInvertido = totalInver;
        _utilidadGenerada = utilGenerada;
        _isLoading = false;
      });
    } catch (e) {
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
                  Container(
                    decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Colors.white24, width: 1)),
                    child: CircleAvatar(backgroundColor: const Color(0xFF163E6E), radius: 22, child: Text(_getInitial(), style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold))),
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
            color: Colors.white,
            width: double.infinity,
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('VISIÓN GENERAL DE CARTERA (HOY)', style: TextStyle(color: Colors.grey, fontSize: 14, letterSpacing: 1.2, fontWeight: FontWeight.w600)),
                const Spacer(),
                Center(child: Text('No hay clientes programados para hoy.', style: TextStyle(color: Colors.grey[400], fontSize: 16))),
                const Spacer()
              ]
            )
          )
        )
      ]
    );
  }
}
