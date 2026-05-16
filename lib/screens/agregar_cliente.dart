import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:flutter/foundation.dart' show kIsWeb;

class AgregarClienteScreen extends StatefulWidget {
  const AgregarClienteScreen({super.key});

  @override
  State<AgregarClienteScreen> createState() => _AgregarClienteScreenState();
}

class _AgregarClienteScreenState extends State<AgregarClienteScreen> {
  final TextEditingController _nombreController = TextEditingController();
  final TextEditingController _telefonoController = TextEditingController();
  final TextEditingController _direccionController = TextEditingController();
  final TextEditingController _prestamoController = TextEditingController();
  
  String? _cobradorSeleccionado;
  List<dynamic> _cobradores = [];
  bool _isLoading = false;

  // Archivos de documentación
  File? _fotoIne;
  File? _fotoComprobante;
  File? _fotoContrato;
  
  // Archivos bytes para web fallback
  Uint8List? _fotoIneBytes;
  Uint8List? _fotoComprobanteBytes;
  Uint8List? _fotoContratoBytes;

  // GPS
  Position? _ubicacionActual;
  bool _obteniendoGps = false;

  // Configuracion Global
  Map<String, dynamic> _config = {};
  
  // Simulacion Calculos
  double _montoTotalPagar = 0;
  double _cuotaDiaria = 0;
  int _plazoDias = 0;
  DateTime? _fechaFin;
  double _simulacionMoratorio = 0;
  double _simulacionPenalizacionGrave = 0;

  @override
  void initState() {
    super.initState();
    _fetchInitialData();
    _prestamoController.addListener(_calcularPlan);
  }

  Future<void> _fetchInitialData() async {
    final responseCobradores = await Supabase.instance.client.from('perfiles').select().eq('rol', 'cobrador');
    final responseConfig = await Supabase.instance.client.from('configuracion').select().eq('id', 1).single();

    if(mounted) {
      setState(() {
        _cobradores = responseCobradores;
        _config = responseConfig;
      });
    }
  }

  void _calcularPlan() {
    if (_config.isEmpty) return;
    
    double monto = double.tryParse(_prestamoController.text) ?? 0.0;
    if (monto <= 0) {
      setState(() {
        _montoTotalPagar = 0;
        _cuotaDiaria = 0;
        _plazoDias = 0;
        _fechaFin = null;
        _simulacionMoratorio = 0;
        _simulacionPenalizacionGrave = 0;
      });
      return;
    }

    double interes = (_config['tasa_interes_base'] ?? 25) / 100;
    double pCuota = (_config['porcentaje_cuota_diaria'] ?? 5) / 100;
    
    double totalPagar = monto + (monto * interes);
    double cuota = monto * pCuota;
    int dias = (totalPagar / cuota).ceil();

    int diasAAgregar = dias + (dias ~/ 5) * 2; 
    DateTime finAprox = DateTime.now().add(Duration(days: diasAAgregar));

    // Correccion en simulacion de mora y penalizacion basada en porcentaje del 'monto_principal' (capital)
    double pMora = (_config['porcentaje_mora_diaria'] ?? 1) / 100;
    double pPenalizacion = (_config['penalizacion_incumplimiento_30d'] ?? 10) / 100;

    setState(() {
      _montoTotalPagar = totalPagar;
      _cuotaDiaria = cuota;
      _plazoDias = dias;
      _fechaFin = finAprox;
      _simulacionMoratorio = monto * pMora; // Por dia de mora segun capital (ej 1000 -> 1% = 10)
      _simulacionPenalizacionGrave = monto * pPenalizacion; // Multa grave (ej 1000 -> 10% = 100)
    });
  }

  Future<void> _pickImage(String type) async {
    final ImagePicker picker = ImagePicker();
    final source = await showDialog<ImageSource>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Origen de la imagen'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(leading: const Icon(Icons.camera_alt), title: const Text('Tomar Foto'), onTap: () => Navigator.pop(context, ImageSource.camera)),
            ListTile(leading: const Icon(Icons.photo_library), title: const Text('Galería'), onTap: () => Navigator.pop(context, ImageSource.gallery)),
          ],
        )
      )
    );

    if (source == null) return;

    final XFile? image = await picker.pickImage(source: source, imageQuality: 80);
    if (image != null) {
      final bytes = await image.readAsBytes();
      setState(() {
        if (type == 'ine') { _fotoIne = File(image.path); _fotoIneBytes = bytes; }
        else if (type == 'comprobante') { _fotoComprobante = File(image.path); _fotoComprobanteBytes = bytes; }
        else if (type == 'contrato') { _fotoContrato = File(image.path); _fotoContratoBytes = bytes; }
      });
    }
  }

  Future<String?> _uploadToSupabase(String filename, File? file, Uint8List? bytes) async {
    try {
      if (kIsWeb && bytes != null) {
         await Supabase.instance.client.storage.from('expedientes').uploadBinary(filename, bytes);
      } else if (file != null) {
         await Supabase.instance.client.storage.from('expedientes').upload(filename, file);
      } else {
         return null;
      }
      return Supabase.instance.client.storage.from('expedientes').getPublicUrl(filename);
    } catch (e) {
      print('Error uploading: $e');
      return null;
    }
  }

  Future<void> _obtenerGps() async {
    setState(() => _obteniendoGps = true);
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Permiso GPS denegado')));
          return;
        }
      }
      Position p = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
      setState(() => _ubicacionActual = p);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Ubicación obtenida exitosamente')));
    } catch(e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error GPS: $e')));
    } finally {
      setState(() => _obteniendoGps = false);
    }
  }

  Future<void> _guardarCliente() async {
    if (_nombreController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Por favor, ingrese el nombre completo')));
      return; 
    }
    if (_telefonoController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Por favor, ingrese el teléfono')));
      return; 
    }
    if (_cobradorSeleccionado == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Por favor, seleccione un cobrador asigado')));
      return; 
    }
    if (_prestamoController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Por favor, ingrese la cantidad de préstamo')));
      return; 
    }
    if (_ubicacionActual == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Por favor, recupere la ubicación GPS')));
      return; 
    }

    setState(() => _isLoading = true);

    try {
      final Map<String, dynamic> clienteData = {
        'nombre_completo': _nombreController.text.trim(),
        'telefono': _telefonoController.text.trim(),
        'direccion': _direccionController.text.trim(),
      };

      if (_ubicacionActual != null) {
         clienteData['latitud'] = _ubicacionActual!.latitude;
         clienteData['longitud'] = _ubicacionActual!.longitude;
      }

      final clienteResponse = await Supabase.instance.client.from('clientes').insert(clienteData).select().single();
      final clienteId = clienteResponse['id'] as String;

      String? inev, compv, contv;
      if (_fotoIne != null || _fotoIneBytes != null) inev = await _uploadToSupabase('$clienteId/ine_${DateTime.now().millisecondsSinceEpoch}.jpg', _fotoIne, _fotoIneBytes);
      if (_fotoComprobante != null || _fotoComprobanteBytes != null) compv = await _uploadToSupabase('$clienteId/comprobante_${DateTime.now().millisecondsSinceEpoch}.jpg', _fotoComprobante, _fotoComprobanteBytes);
      if (_fotoContrato != null || _fotoContratoBytes != null) contv = await _uploadToSupabase('$clienteId/contrato_${DateTime.now().millisecondsSinceEpoch}.jpg', _fotoContrato, _fotoContratoBytes);

      if (inev != null || compv != null || contv != null) {
        await Supabase.instance.client.from('clientes').update({
          if (inev != null) 'foto_ine_url': inev,
          if (compv != null) 'foto_comprobante_url': compv,
          if (contv != null) 'contrato_url': contv,
        }).eq('id', clienteId);
      }

      double montoP = double.tryParse(_prestamoController.text) ?? 0.0;
      double intBase = (_config['tasa_interes_base'] ?? 25) / 100;
      double porcentajeCuota = (_config['porcentaje_cuota_diaria'] ?? 5) / 100;

      await Supabase.instance.client.from('prestamos').insert({
        'cliente_id': clienteId,
        'cobrador_id': _cobradorSeleccionado,
        'monto_principal': montoP,
        'monto_total_pagar': montoP + (montoP * intBase),
        'cuota_diaria': montoP * porcentajeCuota,
        'plazo_dias': _plazoDias, 
        'estado': 'activo',
      });

      if (mounted) {
        Navigator.pop(context, true);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Cliente guardado con éxito')));
      }
    } catch (e) {
      print('Error guardando: $e');
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    _nombreController.dispose();
    _telefonoController.dispose();
    _direccionController.dispose();
    _prestamoController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final currencyFormat = NumberFormat.currency(locale: 'es_MX', symbol: '\$');

    return Scaffold(
      backgroundColor: const Color(0xFFF3F4F6),
      appBar: AppBar(
        backgroundColor: const Color(0xFF09305A),
        foregroundColor: Colors.white,
        title: const Text('Agregar Cliente'),
        elevation: 0,
      ),
      body: _isLoading 
        ? const Center(child: CircularProgressIndicator())
        : ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const Text('Datos Personales', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF09305A))),
            const SizedBox(height: 16),
            _buildInput(label: 'Nombre Completo', icon: Icons.person_outline, controller: _nombreController),
            const SizedBox(height: 12),
            _buildInput(label: 'Número de Teléfono', icon: Icons.phone_outlined, controller: _telefonoController, isNumber: true),
            const SizedBox(height: 12),
            _buildInput(label: 'Dirección', icon: Icons.location_on_outlined, controller: _direccionController),
            const SizedBox(height: 12),
            Container(
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
              child: DropdownButtonFormField<String>(
                value: _cobradorSeleccionado,
                decoration: InputDecoration(
                  labelText: 'Cobrador Asignado',
                  prefixIcon: const Icon(Icons.work_outline, color: Colors.grey),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                ),
                items: _cobradores.map((c) => DropdownMenuItem<String>(
                  value: c['id'],
                  child: Text(c['nombre_completo']),
                )).toList(),
                onChanged: (val) => setState(() => _cobradorSeleccionado = val),
              ),
            ),
            const SizedBox(height: 24),

            const Text('Detalles del Préstamo', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF09305A))),
            const SizedBox(height: 16),
            _buildInput(label: 'Cantidad de Préstamo (\$)', icon: Icons.attach_money, controller: _prestamoController, isNumber: true),
            
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.assignment_outlined, color: Color(0xFF09305A), size: 20),
                      SizedBox(width: 8),
                      Text('PLAN DE PAGOS AUTOMÁTICO', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF09305A), fontSize: 12)),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _buildSummaryRow('Total a Pagar (con int.)', currencyFormat.format(_montoTotalPagar), isBold: true),
                  const Divider(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Cuota Diaria', style: TextStyle(color: Colors.black87)),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(color: const Color(0xFFE0E7FF), borderRadius: BorderRadius.circular(4)),
                        child: Text('${currencyFormat.format(_cuotaDiaria)} / DÍA', style: const TextStyle(color: Color(0xFF3730A3), fontWeight: FontWeight.bold)),
                      )
                    ],
                  ),
                  const Divider(height: 24),
                  _buildSummaryRow('Plazo Generado', '$_plazoDias días', isBold: true),
                  const Divider(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Finaliza el', style: TextStyle(color: Colors.black87)),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(color: const Color(0xFFD1FAE5), borderRadius: BorderRadius.circular(4)),
                        child: Text(_fechaFin != null ? '${_fechaFin!.day}/${_fechaFin!.month}/${_fechaFin!.year}' : '-', style: const TextStyle(color: Color(0xFF065F46), fontWeight: FontWeight.bold)),
                      )
                    ],
                  ),
                  const SizedBox(height: 16),
                  const Text('Reglas de Incumplimiento', style: TextStyle(color: Colors.grey, fontSize: 12)),
                  const SizedBox(height: 8),
                  _buildSummaryRow('Moratorio (por día)', '+${currencyFormat.format(_simulacionMoratorio)}', color: Colors.red.shade300),
                  const SizedBox(height: 8),
                  _buildSummaryRow('Penalización Grave', '+${currencyFormat.format(_simulacionPenalizacionGrave)}', color: Colors.red.shade300),
                ],
              ),
            ),
            const SizedBox(height: 24),

            const Text('Documentación', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF09305A))),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildDocButton('INE', _fotoIneBytes, () => _pickImage('ine')),
                _buildDocButton('Comprobante', _fotoComprobanteBytes, () => _pickImage('comprobante')),
                _buildDocButton('Contrato', _fotoContratoBytes, () => _pickImage('contrato')),
              ],
            ),
            const SizedBox(height: 24),

            const Text('Ubicación GPS', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF09305A))),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _obteniendoGps ? null : _obtenerGps,
              style: ElevatedButton.styleFrom(
                backgroundColor: _ubicacionActual != null ? const Color(0xFF065F46) : const Color(0xFF64748B),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              icon: _obteniendoGps 
                ? const SizedBox(width:20, height:20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) 
                : (_ubicacionActual != null ? const Icon(Icons.check_circle_outline) : const Icon(Icons.location_on_outlined)),
              label: Text(_ubicacionActual != null ? 'Ubicación Recuperada' : 'Recuperar Ubicación'),
            ),
            if (_ubicacionActual != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text('Lat: ${_ubicacionActual!.latitude}, Lon: ${_ubicacionActual!.longitude}', style: const TextStyle(color: Colors.grey, fontSize: 12, fontStyle: FontStyle.italic), textAlign: TextAlign.center),
              ),
            const SizedBox(height: 32),

            ElevatedButton(
              onPressed: _guardarCliente,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF09305A),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 18),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('Guardar Cliente', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ),
            const SizedBox(height: 24),
          ],
        ),
    );
  }

  Widget _buildInput({required String label, required IconData icon, required TextEditingController controller, bool isNumber = false}) {
    return Container(
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
      child: TextField(
        controller: controller,
        keyboardType: isNumber ? TextInputType.number : TextInputType.text,
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: Icon(icon, color: Colors.grey),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
        ),
      ),
    );
  }

  Widget _buildSummaryRow(String label, String val, {bool isBold = false, Color color = Colors.black87}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: TextStyle(color: Colors.black87, fontWeight: isBold ? FontWeight.bold : FontWeight.normal)),
        Text(val, style: TextStyle(fontWeight: isBold ? FontWeight.bold : FontWeight.normal, color: color)),
      ],
    );
  }

  Widget _buildDocButton(String label, Uint8List? bytes, VoidCallback onTap) {
    return Column(
      children: [
        InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: bytes != null ? Colors.green : Colors.grey.shade300, width: 2),
            ),
            child: bytes != null 
                ? ClipRRect(borderRadius: BorderRadius.circular(14), child: Image.memory(bytes, fit: BoxFit.cover))
                : const Icon(Icons.camera_alt_outlined, color: Colors.grey, size: 32),
          ),
        ),
        const SizedBox(height: 8),
        Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.black87)),
      ],
    );
  }
}
