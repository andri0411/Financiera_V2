import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';

class CobradorDetalleDueno extends StatefulWidget {
  final String cobradorId;
  final String nombreCompleto;

  const CobradorDetalleDueno({
    super.key,
    required this.cobradorId,
    required this.nombreCompleto,
  });

  @override
  State<CobradorDetalleDueno> createState() => _CobradorDetalleDuenoState();
}

class _CobradorDetalleDuenoState extends State<CobradorDetalleDueno> {
  bool _isLoading = true;
  bool _isSaving = false;

  double _recoleccionSemana = 0;
  double _baseComisionSemana = 0;
  double _comisionPorcentaje = 0;
  String _email = '';
  String _username = '';

  // Controladores para edición
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nombreCtrl;
  late TextEditingController _emailCtrl;
  late TextEditingController _usernameCtrl;
  final TextEditingController _passCtrl = TextEditingController();
  final TextEditingController _passConfirmCtrl = TextEditingController();
  bool _showPass = false;
  bool _showPassConfirm = false;

  final _fmt = NumberFormat.currency(symbol: r'$', decimalDigits: 2, locale: 'es_MX');

  @override
  void initState() {
    super.initState();
    _nombreCtrl = TextEditingController(text: widget.nombreCompleto);
    _emailCtrl = TextEditingController();
    _usernameCtrl = TextEditingController();
    _fetchData();
  }

  @override
  void dispose() {
    _nombreCtrl.dispose();
    _emailCtrl.dispose();
    _usernameCtrl.dispose();
    _passCtrl.dispose();
    _passConfirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _fetchData() async {
    setState(() => _isLoading = true);
    try {
      // Semana actual (lunes a domingo)
      final hoy = DateTime.now().toLocal();
      final lunes = hoy.subtract(Duration(days: hoy.weekday - 1));
      final lunesInicio = DateTime(lunes.year, lunes.month, lunes.day);
      final domingoFin = lunesInicio.add(const Duration(days: 7));

      // Recolección de la semana
      final pagosRes = await Supabase.instance.client
          .from('pagos')
          .select('monto_recibido, monto_cuota_base')
          .eq('registrado_por', widget.cobradorId)
          .gte('fecha_pago', lunesInicio.toUtc().toIso8601String())
          .lt('fecha_pago', domingoFin.toUtc().toIso8601String());

      _recoleccionSemana = (pagosRes as List)
          .fold(0.0, (s, p) => s + ((p['monto_recibido'] ?? 0) as num).toDouble());
      
      _baseComisionSemana = (pagosRes as List)
          .fold(0.0, (s, p) => s + ((p['monto_cuota_base'] ?? 0) as num).toDouble());

      // Comisión configurada
      final configRes = await Supabase.instance.client
          .from('configuracion')
          .select('comision_porcentaje')
          .limit(1)
          .maybeSingle();
      _comisionPorcentaje = ((configRes?['comision_porcentaje'] ?? 0) as num).toDouble();

      // Perfil del cobrador
      final perfilRes = await Supabase.instance.client
          .from('perfiles')
          .select('nombre_completo, username, email')
          .eq('id', widget.cobradorId)
          .maybeSingle();

      if (perfilRes != null) {
        _nombreCtrl.text = perfilRes['nombre_completo'] ?? widget.nombreCompleto;
        _email = perfilRes['email'] ?? '';
        _username = perfilRes['username'] ?? '';
        _emailCtrl.text = _email;
        _usernameCtrl.text = _username;
      }
    } catch (e) {
      _snack('Error al cargar datos: $e', isError: true);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _guardar() async {
    if (!_formKey.currentState!.validate()) return;
    if (_passCtrl.text.isNotEmpty && _passCtrl.text != _passConfirmCtrl.text) {
      _snack('Las contraseñas no coinciden.', isError: true);
      return;
    }
    setState(() => _isSaving = true);
    try {
      // Actualizar perfil
      await Supabase.instance.client.from('perfiles').update({
        'nombre_completo': _nombreCtrl.text.trim(),
        'username': _usernameCtrl.text.trim(),
        'email': _emailCtrl.text.trim(),
      }).eq('id', widget.cobradorId);

      // Si se quiere cambiar contraseña, usar admin API
      if (_passCtrl.text.isNotEmpty) {
        await Supabase.instance.client.rpc('fn_admin_update_user_password', params: {
          'p_user_id': widget.cobradorId,
          'p_new_password': _passCtrl.text,
        });
      }

      _snack('Datos actualizados correctamente.');
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      _snack('Error al guardar: $e', isError: true);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _snack(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: isError ? const Color(0xFFDC2626) : const Color(0xFF22C55E),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ));
  }

  void _abrirEdicion() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _EditarCobradorSheet(
        formKey: _formKey,
        nombreCtrl: _nombreCtrl,
        emailCtrl: _emailCtrl,
        usernameCtrl: _usernameCtrl,
        passCtrl: _passCtrl,
        passConfirmCtrl: _passConfirmCtrl,
        isSaving: _isSaving,
        onGuardar: _guardar,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final inicial = (widget.nombreCompleto.isNotEmpty)
        ? widget.nombreCompleto[0].toUpperCase()
        : '?';
    final comisionMonto = _baseComisionSemana * (_comisionPorcentaje / 100);

    return Scaffold(
      backgroundColor: const Color(0xFFF3F4F6),
      body: SafeArea(
        child: _isLoading
            ? const Center(child: CircularProgressIndicator(color: Color(0xFF09305A)))
            : Column(
                children: [
                  // App bar personalizada
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    child: Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.arrow_back, color: Color(0xFF09305A)),
                          onPressed: () => Navigator.pop(context),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                      child: Column(
                        children: [
                          // Avatar
                          Container(
                            width: 80,
                            height: 80,
                            decoration: const BoxDecoration(
                              color: Color(0xFF09305A),
                              shape: BoxShape.circle,
                            ),
                            child: Center(
                              child: Text(
                                inicial,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 32,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 14),
                          Text(
                            _nombreCtrl.text,
                            style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF09305A),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.email_outlined, size: 14, color: Colors.grey),
                              const SizedBox(width: 4),
                              Text(
                                _emailCtrl.text,
                                style: const TextStyle(color: Colors.grey, fontSize: 13),
                              ),
                            ],
                          ),
                          const SizedBox(height: 28),

                          // Card: Recolección de la semana
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(24),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(20),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.05),
                                  blurRadius: 12,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: const [
                                    Icon(Icons.calendar_today_outlined, size: 16, color: Color(0xFF09305A)),
                                    SizedBox(width: 8),
                                    Text(
                                      'RECOLECCIÓN DE LA SEMANA',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                        color: Color(0xFF09305A),
                                        letterSpacing: 1.2,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                const Text(
                                  'Total recolectado de Lunes a Domingo',
                                  style: TextStyle(fontSize: 12, color: Colors.grey),
                                ),
                                const SizedBox(height: 14),
                                Text(
                                  _fmt.format(_recoleccionSemana),
                                  style: const TextStyle(
                                    fontSize: 32,
                                    fontWeight: FontWeight.w800,
                                    color: Color(0xFF09305A),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),

                          // Card: Comisión estimada
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(24),
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [Color(0xFF1DB97B), Color(0xFF17A868)],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              borderRadius: BorderRadius.circular(20),
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(0xFF1DB97B).withOpacity(0.35),
                                  blurRadius: 16,
                                  offset: const Offset(0, 6),
                                ),
                              ],
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Row(
                                      children: const [
                                        Icon(Icons.monetization_on_outlined, size: 16, color: Colors.white),
                                        SizedBox(width: 8),
                                        Text(
                                          'COMISIÓN ESTIMADA',
                                          style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w700,
                                            color: Colors.white,
                                            letterSpacing: 1.2,
                                          ),
                                        ),
                                      ],
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: Colors.white.withOpacity(0.25),
                                        borderRadius: BorderRadius.circular(100),
                                      ),
                                      child: Text(
                                        '${_comisionPorcentaje.toStringAsFixed(1)}%',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 14),
                                Text(
                                  _fmt.format(comisionMonto),
                                  style: const TextStyle(
                                    fontSize: 32,
                                    fontWeight: FontWeight.w800,
                                    color: Colors.white,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 24),

                          // Botón editar
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              onPressed: _abrirEdicion,
                              icon: const Icon(Icons.edit_outlined, size: 18, color: Color(0xFF09305A)),
                              label: const Text(
                                'Editar / Reasignar Cobrador',
                                style: TextStyle(
                                  color: Color(0xFF09305A),
                                  fontWeight: FontWeight.w700,
                                  fontSize: 15,
                                ),
                              ),
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(vertical: 16),
                                side: const BorderSide(color: Color(0xFF09305A), width: 1.5),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                              ),
                            ),
                          ),
                          const SizedBox(height: 32),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

// ── Bottom Sheet de Edición ─────────────────────────────────────
class _EditarCobradorSheet extends StatefulWidget {
  final GlobalKey<FormState> formKey;
  final TextEditingController nombreCtrl;
  final TextEditingController emailCtrl;
  final TextEditingController usernameCtrl;
  final TextEditingController passCtrl;
  final TextEditingController passConfirmCtrl;
  final bool isSaving;
  final VoidCallback onGuardar;

  const _EditarCobradorSheet({
    required this.formKey,
    required this.nombreCtrl,
    required this.emailCtrl,
    required this.usernameCtrl,
    required this.passCtrl,
    required this.passConfirmCtrl,
    required this.isSaving,
    required this.onGuardar,
  });

  @override
  State<_EditarCobradorSheet> createState() => _EditarCobradorSheetState();
}

class _EditarCobradorSheetState extends State<_EditarCobradorSheet> {
  bool _showPass = false;
  bool _showPassConfirm = false;

  InputDecoration _inputDeco(String label, IconData icon) => InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Color(0xFF09305A)),
        prefixIcon: Icon(icon, color: const Color(0xFF09305A), size: 20),
        filled: true,
        fillColor: const Color(0xFFF9FAFB),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFF09305A), width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFFDC2626)),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFFDC2626), width: 1.5),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: SingleChildScrollView(
        child: Form(
          key: widget.formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Handle
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 20),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE5E7EB),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
              const Text(
                'Editar Cobrador',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF09305A),
                ),
              ),
              const SizedBox(height: 20),

              // Nombre
              TextFormField(
                controller: widget.nombreCtrl,
                decoration: _inputDeco('Nombre completo', Icons.person_outline),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Campo requerido' : null,
              ),
              const SizedBox(height: 14),

              // Email
              TextFormField(
                controller: widget.emailCtrl,
                keyboardType: TextInputType.emailAddress,
                decoration: _inputDeco('Correo electrónico', Icons.email_outlined),
                validator: (v) => (v == null || !v.contains('@')) ? 'Correo inválido' : null,
              ),
              const SizedBox(height: 14),

              // Username
              TextFormField(
                controller: widget.usernameCtrl,
                decoration: _inputDeco('Username', Icons.alternate_email),
              ),
              const SizedBox(height: 14),

              // Divider nueva contraseña
              Row(children: [
                const Expanded(child: Divider()),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 12),
                  child: Text('Nueva contraseña (opcional)', style: TextStyle(color: Colors.grey, fontSize: 12)),
                ),
                const Expanded(child: Divider()),
              ]),
              const SizedBox(height: 14),

              // Contraseña
              TextFormField(
                controller: widget.passCtrl,
                obscureText: !_showPass,
                decoration: _inputDeco('Contraseña', Icons.lock_outline).copyWith(
                  suffixIcon: IconButton(
                    icon: Icon(_showPass ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                        color: Colors.grey, size: 20),
                    onPressed: () => setState(() => _showPass = !_showPass),
                  ),
                ),
              ),
              const SizedBox(height: 14),

              // Confirmar contraseña
              TextFormField(
                controller: widget.passConfirmCtrl,
                obscureText: !_showPassConfirm,
                decoration: _inputDeco('Confirmar contraseña', Icons.lock_outline).copyWith(
                  suffixIcon: IconButton(
                    icon: Icon(_showPassConfirm ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                        color: Colors.grey, size: 20),
                    onPressed: () => setState(() => _showPassConfirm = !_showPassConfirm),
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // Botón guardar
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: widget.isSaving ? null : widget.onGuardar,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF09305A),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    elevation: 0,
                  ),
                  child: widget.isSaving
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                        )
                      : const Text(
                          'Guardar cambios',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
