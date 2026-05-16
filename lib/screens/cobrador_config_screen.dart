import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class CobradorConfigScreen extends StatefulWidget {
  const CobradorConfigScreen({super.key});

  @override
  State<CobradorConfigScreen> createState() => _CobradorConfigScreenState();
}

class _CobradorConfigScreenState extends State<CobradorConfigScreen> {
  Future<void> _cerrarSesion() async {
    await Supabase.instance.client.auth.signOut();
    if (mounted) {
      // Navegamos al login y limpiamos la pila
      Navigator.pushNamedAndRemoveUntil(context, '/', (route) => false);
    }
  }

  void _conectarImpresora() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('La función de impresora Bluetooth está en desarrollo.'),
        behavior: SnackBarBehavior.floating,
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
                    color: const Color(0xFFF3F4F6),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.print_outlined,
                    color: Color(0xFF09305A),
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
                subtitle: const Text(
                  'Conectar para imprimir tickets',
                  style: TextStyle(
                    color: Colors.grey,
                    fontSize: 12,
                  ),
                ),
                trailing: const Icon(Icons.chevron_right_rounded, color: Colors.grey),
                onTap: _conectarImpresora,
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
