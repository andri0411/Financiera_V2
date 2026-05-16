import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AgregarCobradorScreen extends StatefulWidget {
  const AgregarCobradorScreen({super.key});

  @override
  State<AgregarCobradorScreen> createState() => _AgregarCobradorScreenState();
}

class _AgregarCobradorScreenState extends State<AgregarCobradorScreen> {
  final TextEditingController _nombreController = TextEditingController();
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _correoController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  
  bool _isLoading = false;
  bool _obscureText = true;

  Future<void> _guardarCobrador() async {
    if (_nombreController.text.isEmpty || _usernameController.text.isEmpty || _correoController.text.isEmpty || _passwordController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Por favor, llena todos los campos'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      await Supabase.instance.client.rpc(
        'fn_crear_cobrador',
        params: {
          'p_username': _usernameController.text.trim(),
          'p_email': _correoController.text.trim(),
          'p_password': _passwordController.text,
          'p_nombre': _nombreController.text.trim(),
        },
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Cobrador registrado exitosamente'),
            backgroundColor: Color(0xFF22C55E),
            behavior: SnackBarBehavior.floating,
          ),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      print('Error al guardar cobrador: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.redAccent,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  void dispose() {
    _nombreController.dispose();
    _usernameController.dispose();
    _correoController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF9FAFB),
      appBar: AppBar(
        backgroundColor: const Color(0xFF09305A),
        foregroundColor: Colors.white,
        title: const Text(
          'Nuevo Cobrador',
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 20),
        ),
        elevation: 0,
        centerTitle: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(bottom: Radius.circular(20)),
        ),
      ),
      body: _isLoading 
        ? const Center(child: CircularProgressIndicator(color: Color(0xFF09305A)))
        : SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'INFORMACIÓN PERSONAL', 
                  style: TextStyle(
                    fontWeight: FontWeight.w800, 
                    fontSize: 12, 
                    color: Color(0xFF6B7280),
                    letterSpacing: 1.2,
                  )
                ),
                const SizedBox(height: 16),
                
                _buildTextField(
                  controller: _nombreController,
                  hint: 'Nombre Completo',
                  icon: Icons.person_rounded,
                ),
                const SizedBox(height: 24),

                const Text(
                  'CREDENCIALES DE ACCESO', 
                  style: TextStyle(
                    fontWeight: FontWeight.w800, 
                    fontSize: 12, 
                    color: Color(0xFF6B7280),
                    letterSpacing: 1.2,
                  )
                ),
                const SizedBox(height: 16),

                _buildTextField(
                  controller: _usernameController,
                  hint: 'Nombre de Usuario',
                  icon: Icons.badge_rounded,
                ),
                const SizedBox(height: 16),

                _buildTextField(
                  controller: _correoController,
                  hint: 'Correo Electrónico',
                  icon: Icons.alternate_email_rounded,
                  keyboardType: TextInputType.emailAddress,
                ),
                const SizedBox(height: 16),

                _buildTextField(
                  controller: _passwordController,
                  hint: 'Contraseña',
                  icon: Icons.lock_rounded,
                  isPassword: true,
                ),

                const SizedBox(height: 40),
                
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _guardarCobrador,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF09305A),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 20),
                      elevation: 4,
                      shadowColor: const Color(0xFF09305A).withOpacity(0.4),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16)
                      ),
                    ),
                    child: const Text(
                      'CREAR COBRADOR', 
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, letterSpacing: 0.5)
                    ),
                  ),
                ),
              ],
            ),
          ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    bool isPassword = false,
    TextInputType keyboardType = TextInputType.text,
  }) {
    return Container(
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
      child: TextField(
        controller: controller,
        obscureText: isPassword ? _obscureText : false,
        keyboardType: keyboardType,
        style: const TextStyle(fontWeight: FontWeight.w600, color: Color(0xFF09305A)),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: const TextStyle(color: Color(0xFF9CA3AF), fontWeight: FontWeight.w500),
          prefixIcon: Icon(icon, color: const Color(0xFF09305A)),
          suffixIcon: isPassword 
            ? IconButton(
                icon: Icon(_obscureText ? Icons.visibility_off_rounded : Icons.visibility_rounded, color: const Color(0xFF9CA3AF)),
                onPressed: () => setState(() => _obscureText = !_obscureText),
              )
            : null,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16), 
            borderSide: BorderSide.none
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
        ),
      ),
    );
  }
}
