// ignore_for_file: avoid_print, use_build_context_synchronously
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'admin_dashboard.dart';
import 'cobrador_main.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController _userController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  bool _isLoading = false;

  Future<void> _iniciarSesion() async {
    final usuario = _userController.text.trim();
    final password = _passwordController.text;

    if (usuario.isEmpty || password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Por favor, ingresa usuario y contraseña'),
        ),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      print('--- INTENTANDO INICIAR SESIÓN CON: $usuario ---');
      // Determinamos el email. Si contiene '@', lo usamos tal cual (Dueño). Si no, asumimos que es cobrador y usamos el correo ficticio o username si la BD lo permite.
      // Sin embargo, Supabase Auth con email requiere formato email. El Dueño usa correo válido, el cobrador si pone su correo o su username (mapeado a username@sistema.com)
      AuthResponse? res;
      try {
        // Intentamos asumir que es un correo (o un username guardado sin dominio)
        res = await Supabase.instance.client.auth.signInWithPassword(email: usuario, password: password);
      } catch (e) {
        // Si falla, intentamos buscar si hay un correo asociado a ese username en la BD
        print('--- FALLÓ LOGIN DIRECTO. BUSCANDO CORREO POR USERNAME ---');
        try {
          final emailResult = await Supabase.instance.client.rpc('fn_obtener_email_por_username', params: {'p_username': usuario});
          
          if (emailResult != null && emailResult.toString().isNotEmpty) {
            print('--- CORREO ENCONTRADO: $emailResult. INTENTANDO LOGIN NUEVAMENTE ---');
            res = await Supabase.instance.client.auth.signInWithPassword(email: emailResult.toString(), password: password);
          } else {
            // Si tampoco encuentra correo, probamos con el @sistema.com heredado por si acaso
            res = await Supabase.instance.client.auth.signInWithPassword(email: '$usuario@sistema.com', password: password);
          }
        } catch (e2) {
          rethrow;
        }
      }

      final Session? session = res.session;
      final User? user = res.user;

      if (session != null && user != null) {
        print('--- INICIO DE SESIÓN EXITOSO. BUSCANDO ROL ---');
        print('--- USER ID: ${user.id} ---');

        // Buscar rol en la tabla perfiles
        var perfilRes = await Supabase.instance.client
            .from('perfiles')
            .select()
            .eq('id', user.id)
            .maybeSingle();

        if (perfilRes == null) {
          print('--- FALLÓ SELECT DIRECTO. INTENTANDO CON RPC fn_obtener_mi_perfil ---');
          try {
            final rpcRes = await Supabase.instance.client.rpc('fn_obtener_mi_perfil', params: {'p_user_id': user.id});
            if (rpcRes != null) {
              perfilRes = Map<String, dynamic>.from(rpcRes);
              print('--- PERFIL ENCONTRADO VIA RPC ---');
            }
          } catch (e) {
            print('--- ERROR EN RPC fn_obtener_mi_perfil: $e ---');
          }
        }

        if (perfilRes != null) {
          final rol = perfilRes['rol'];
          print('--- ROL ENCONTRADO: $rol ---');

          if (!mounted) return;

          if (rol == 'admin') {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                builder: (context) => AdminDashboard(perfil: perfilRes as Map<String, dynamic>),
              ),
            );
          } else if (rol == 'cobrador') {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                builder: (context) => const CobradorMainScreen(),
              ),
            );
          } else {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(const SnackBar(content: Text('Rol desconocido')));
          }
        } else {
          print('--- NO SE ENCONTRÓ EL PERFIL DEL USUARIO ---');
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Perfil de usuario no encontrado en la base de datos',
              ),
            ),
          );
        }
      }
    } on AuthException catch (error) {
      print('--- ERROR DE AUTENTICACION: ${error.message} ---');
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error: ${error.message}')));
    } catch (e) {
      print('--- ERROR DESCONOCIDO: $e ---');
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error inesperado: $e')));
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _userController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(
        0xFFF3F4F6,
      ), // Color de fondo gris claro, basado en la imagen
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Logo de la aplicación
                Image.asset(
                  'assets/logo_completo.png',
                  height: 120,
                  fit: BoxFit.contain,
                ),
                const SizedBox(height: 10),
                // Texto Inicia sesión para continuar
                const Text(
                  'Inicia sesión para continuar',
                  style: TextStyle(fontSize: 16, color: Colors.grey),
                ),
                const SizedBox(height: 40),
                // Campo de Usuario
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: TextField(
                    controller: _userController,
                    decoration: const InputDecoration(
                      hintText: 'Usuario',
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 18,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                // Campo de Contraseña
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: TextField(
                    controller: _passwordController,
                    obscureText: true,
                    decoration: const InputDecoration(
                      hintText: 'Contraseña',
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 18,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 32),
                // Botón Iniciar Sesión
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _iniciarSesion,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(
                        0xFF09305A,
                      ), // Azul oscuro (basado en el UI)
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 18),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: _isLoading
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          )
                        : const Text(
                            'Iniciar Sesión',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
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
