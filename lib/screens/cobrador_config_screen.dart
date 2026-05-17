import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:blue_thermal_printer/blue_thermal_printer.dart';
import 'package:flutter/services.dart';
import 'config_ticket_screen.dart';

class CobradorConfigScreen extends StatefulWidget {
  const CobradorConfigScreen({super.key});

  @override
  State<CobradorConfigScreen> createState() => _CobradorConfigScreenState();
}

class _CobradorConfigScreenState extends State<CobradorConfigScreen> {
  final BlueThermalPrinter _bluetooth = BlueThermalPrinter.instance;
  bool _isConnected = false;
  BluetoothDevice? _connectedDevice;

  @override
  void initState() {
    super.initState();
    _checkConnection();
  }

  Future<void> _checkConnection() async {
    try {
      bool? connected = await _bluetooth.isConnected;
      if (mounted) setState(() => _isConnected = connected ?? false);
    } catch (_) {}
  }

  Future<void> _cerrarSesion() async {
    await Supabase.instance.client.auth.signOut();
    if (mounted) {
      Navigator.pushNamedAndRemoveUntil(context, '/', (route) => false);
    }
  }

  Future<void> _abrirImpresora() async {
    List<BluetoothDevice> devices = [];
    try {
      devices = await _bluetooth.getBondedDevices();
    } on PlatformException {
      // ignore
    }
    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => BluetoothPrinterScreen(
          bluetooth: _bluetooth,
          initialDevices: devices,
          connectedDevice: _isConnected ? _connectedDevice : null,
          onDeviceConnected: (device) {
            setState(() {
              _connectedDevice = device;
              _isConnected = true;
            });
          },
          onDeviceDisconnected: () {
            setState(() {
              _connectedDevice = null;
              _isConnected = false;
            });
          },
        ),
      ),
    );
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF9FAFB),
      appBar: AppBar(
        backgroundColor: const Color(0xFF09305A),
        foregroundColor: Colors.white,
        title: const Text(
          'Configuración',
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 20),
        ),
        elevation: 0,
        centerTitle: false,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            // Tarjeta de Impresora Bluetooth
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.04),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                leading: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: _isConnected ? const Color(0xFFDCFCE7) : const Color(0xFFF3F4F6),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.print_outlined,
                    color: _isConnected ? const Color(0xFF16A34A) : const Color(0xFF09305A),
                  ),
                ),
                title: const Text(
                  'Impresora Bluetooth',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF09305A),
                    fontSize: 16,
                  ),
                ),
                subtitle: Text(
                  _isConnected ? 'Conectada • Toca para cambiar' : 'Conectar para imprimir tickets',
                  style: TextStyle(
                    color: _isConnected ? const Color(0xFF16A34A) : Colors.grey,
                    fontSize: 12,
                  ),
                ),
                trailing: const Icon(Icons.chevron_right_rounded, color: Colors.grey),
                onTap: _abrirImpresora,
              ),
            ),
            
            const SizedBox(height: 24),
            
            // Botón de Cerrar Sesión
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _cerrarSesion,
                icon: const Icon(Icons.logout_rounded, color: Colors.white),
                label: const Text(
                  'Cerrar Sesión',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFDC2626), // Rojo
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  elevation: 0,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
