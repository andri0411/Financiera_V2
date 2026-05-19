import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:image_picker/image_picker.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';
import 'admin_renovacion_detalle_screen.dart';

class ClienteDetalleScreen extends StatefulWidget {
  final Map<String, dynamic> cliente;

  const ClienteDetalleScreen({super.key, required this.cliente});

  @override
  State<ClienteDetalleScreen> createState() => _ClienteDetalleScreenState();
}

class _ClienteDetalleScreenState extends State<ClienteDetalleScreen> {
  final formatter = NumberFormat.currency(locale: 'es_MX', symbol: '\$');
  bool _isLoading = true;
  Map<String, dynamic>? _prestamoActivo;
  List<dynamic> _cuotas = [];
  Map<String, dynamic>? _clienteActualizado;
  Map<String, dynamic>? _atencionHoy;

  @override
  void initState() {
    super.initState();
    _fetchDetalles();
  }

  Future<void> _fetchDetalles() async {
    try {
      // 1. Refrescar cliente
      final resCliente = await Supabase.instance.client
          .from('clientes')
          .select()
          .eq('id', widget.cliente['id'])
          .single();

      // Consultar atencion diaria de hoy
      final hoyStr = DateTime.now().toLocal().toIso8601String().split('T')[0];
      final resAtencion = await Supabase.instance.client
          .from('atencion_diaria')
          .select()
          .eq('cliente_id', widget.cliente['id'])
          .eq('fecha', hoyStr)
          .maybeSingle();

      // 2. Traer el ultimo prestamo (puede ser activo, liquidado o renovado)
      final resPrestamoList = await Supabase.instance.client
          .from('prestamos')
          .select('*, perfiles(nombre_completo)')
          .eq('cliente_id', widget.cliente['id'])
          .order('created_at', ascending: false)
          .limit(1);

      final resPrestamo = resPrestamoList.isNotEmpty ? resPrestamoList.first : null;

      if (resPrestamo != null) {
        _prestamoActivo = resPrestamo;
        
        // 3. Traer cuotas ordenadas por número
        final resCuotas = await Supabase.instance.client
            .from('cuotas')
            .select()
            .eq('prestamo_id', resPrestamo['id'])
            .order('numero_cuota', ascending: true);
            
        _cuotas = resCuotas;
      }

      setState(() {
        _clienteActualizado = resCliente;
        _atencionHoy = resAtencion;
        _isLoading = false;
      });
    } catch (e) {
      print('Error fetching details: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _llamarCliente() async {
    final t = _clienteActualizado?['telefono'] ?? widget.cliente['telefono'];
    if (t == null || t.isEmpty) return;
    final Uri url = Uri.parse("tel:$t");
    try {
      await launchUrl(url); // Abre la app de marcado directamente
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No se pudo abrir el teléfono')));
    }
  }

  Future<void> _abrirMapa() async {
    // Tomar las nuevas columnas del modelo: latitud y longitud
    final lat = _clienteActualizado?['latitud'] ?? widget.cliente['latitud'];
    final lng = _clienteActualizado?['longitud'] ?? widget.cliente['longitud'];

    if (lat != null && lng != null) {
      // Abre la app de mapas por defecto del usuario (Google Maps, etc) con ruta ya trazada
      final Uri url = Uri.parse("https://www.google.com/maps/dir/?api=1&destination=$lat,$lng");
      try {
        await launchUrl(url, mode: LaunchMode.externalApplication);
        return;
      } catch (e) {
        // Ignorar para caer en el fallback
      }
    }

    // Fallback a dirección si el GPS no viene o falla
    final d = _clienteActualizado?['direccion'] ?? widget.cliente['direccion'];
    if (d != null && d.isNotEmpty) {
      final Uri url = Uri.parse("https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent(d)}");
      try {
        await launchUrl(url, mode: LaunchMode.externalApplication);
        return;
      } catch (e) {
        // Ignorar error
      }
    }

    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No hay ubicación GPS guardada')));
  }

  Future<void> _actualizarGPS() async {
    bool confirm = await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Actualizar GPS'),
        content: const Text('¿Desea registrar su ubicación actual como la nueva ubicación del cliente?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Confirmar')),
        ],
      ),
    ) ?? false;

    if (!confirm) return;

    try {
      Position p = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
      await Supabase.instance.client.from('clientes').update({
        'latitud': p.latitude,
        'longitud': p.longitude
      }).eq('id', widget.cliente['id']);
      
      await _fetchDetalles(); // Recargar datos
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('GPS Actualizado correctamente')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error al actualizar GPS: $e')));
    }
  }

  Future<void> _cambiarDocumento(String campoDB, String nombreArchivo) async {
    final ImagePicker picker = ImagePicker();
    final source = await showDialog<ImageSource>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Origen del documento'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(leading: const Icon(Icons.camera_alt), title: const Text('Cámara'), onTap: () => Navigator.pop(context, ImageSource.camera)),
            ListTile(leading: const Icon(Icons.photo_library), title: const Text('Galería'), onTap: () => Navigator.pop(context, ImageSource.gallery)),
          ],
        )
      )
    );

    if (source == null) return;
    
    setState(() => _isLoading = true);
    try {
      final XFile? image = await picker.pickImage(source: source, imageQuality: 80);
      if (image != null) {
        final bytes = await image.readAsBytes();
        final pathObj = '${widget.cliente['id']}/${nombreArchivo}_${DateTime.now().millisecondsSinceEpoch}.jpg';
        
        String urlPublica = '';
        if (kIsWeb) {
           await Supabase.instance.client.storage.from('expedientes').uploadBinary(pathObj, bytes);
        } else {
           await Supabase.instance.client.storage.from('expedientes').upload(pathObj, File(image.path));
        }
        urlPublica = Supabase.instance.client.storage.from('expedientes').getPublicUrl(pathObj);

        await Supabase.instance.client.from('clientes').update({
          campoDB: urlPublica
        }).eq('id', widget.cliente['id']);
        
        await _fetchDetalles();
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Documento actualizado')));
      } else {
        setState(() => _isLoading = false);
      }
    } catch (e) {
      print(e);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Error al subir el documento')));
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        backgroundColor: Color(0xFFF9FAFB),
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final clienteInfo = _clienteActualizado ?? widget.cliente;
    final int atrasosConteoGeneral = (_prestamoActivo != null) ? ((_prestamoActivo!['cuotas_atrasadas_conteo'] ?? 0) as int) : 0;
    
    List<Map<String, dynamic>> cuotasMostrar = List<Map<String, dynamic>>.from(_cuotas);
    if (atrasosConteoGeneral > 0 && cuotasMostrar.isNotEmpty) {
      Map<String, dynamic> ultimaCuota = cuotasMostrar.last;
      DateTime ultimaFecha = DateTime.tryParse(ultimaCuota['fecha_vencimiento'] ?? '') ?? DateTime.now();
      double montoCuotaDiaria = (_prestamoActivo!['cuota_diaria'] ?? 0).toDouble();
      
      for (int i = 0; i < atrasosConteoGeneral; i++) {
        ultimaFecha = ultimaFecha.add(const Duration(days: 1));
        if (ultimaFecha.weekday == DateTime.sunday) {
          ultimaFecha = ultimaFecha.add(const Duration(days: 1));
        }
        cuotasMostrar.add({
          'numero_cuota': _cuotas.length + i + 1,
          'monto_cuota': montoCuotaDiaria,
          'estado_pago': 'pendiente',
          'fecha_vencimiento': ultimaFecha.toIso8601String(),
          'virtual': true
        });
      }
    }

    final int totalCuotas = _cuotas.length;
    final int cuotasPagadas = cuotasMostrar.where((c) => c['estado_pago'] == 'pagado').length;
    final double progreso = totalCuotas == 0 ? 0 : (cuotasPagadas / totalCuotas);
    final idClienteShort = clienteInfo['id'].toString().substring(0, 8).toUpperCase();

    return Scaffold(
      backgroundColor: const Color(0xFFF9FAFB),
      appBar: AppBar(
        title: const Text('Atrás', style: TextStyle(color: Color(0xFF09305A), fontSize: 16, fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFFF9FAFB),
        foregroundColor: const Color(0xFF09305A),
        elevation: 0,
        titleSpacing: 0,
        actions: [
           Container(
             margin: const EdgeInsets.only(right: 16, top: 12, bottom: 12),
             padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
             decoration: BoxDecoration(
               color: const Color(0xFFFEF3C7),
               borderRadius: BorderRadius.circular(8),
             ),
             alignment: Alignment.center,
             child: const Text('PRIORITARIO', style: TextStyle(color: Color(0xFFD97706), fontWeight: FontWeight.bold, fontSize: 12)),
           )
        ],
      ),
      body: _prestamoActivo == null 
        ? const Center(child: Text("El cliente no tiene préstamos."))
        : ListView(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            children: [
              // Header Cliente
              Text(
                clienteInfo['nombre_completo'],
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Color(0xFF09305A)),
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  const Icon(Icons.verified_outlined, size: 16, color: Colors.blue),
                  const SizedBox(width: 4),
                  Text('#$idClienteShort', style: const TextStyle(color: Colors.grey, fontSize: 13, fontWeight: FontWeight.bold)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      clienteInfo['direccion'] ?? 'Sin dirección', 
                      style: const TextStyle(color: Colors.grey, fontSize: 13),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // Fila Crédito & Botones Acción
              if (_prestamoActivo!['estado'] == 'activo')
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Tarjeta Crédito Progreso
                    Expanded(
                      flex: 5,
                      child: Container(
                        height: 110,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.grey.shade200),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('CRÉDITO', style: TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.bold)),
                            Text('$cuotasPagadas / $totalCuotas', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Color(0xFF09305A))),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: LinearProgressIndicator(
                                value: progreso,
                                backgroundColor: Colors.grey.shade200,
                                color: const Color(0xFF09305A),
                                minHeight: 4,
                              ),
                            ),
                            Text('Vence: ${totalCuotas - cuotasPagadas} cuotas rest.', style: const TextStyle(fontSize: 11, color: Colors.grey)),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    // Botones Contacto
                    Expanded(
                      flex: 5,
                      child: SizedBox(
                        height: 110,
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            _buildActionBtn('Llamar', Icons.phone_outlined, const Color(0xFFE0F2FE), Colors.blue.shade700, onTap: _llamarCliente, fullWidth: true),
                            Row(
                              children: [
                                Expanded(child: _buildActionBtn('Mapa', Icons.location_on_outlined, const Color(0xFFDCFCE7), Colors.green.shade700, onTap: _abrirMapa)),
                                const SizedBox(width: 8),
                                Expanded(child: _buildActionBtn('GPS', Icons.sync, const Color(0xFFFFE4E6), Colors.red.shade700, onTap: _actualizarGPS)),
                              ],
                            )
                          ],
                        ),
                      ),
                    ),
                  ],
                )
              else
                SizedBox(
                  height: 110,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _buildActionBtn('Llamar', Icons.phone_outlined, const Color(0xFFE0F2FE), Colors.blue.shade700, onTap: _llamarCliente, fullWidth: true),
                      Row(
                        children: [
                          Expanded(child: _buildActionBtn('Mapa', Icons.location_on_outlined, const Color(0xFFDCFCE7), Colors.green.shade700, onTap: _abrirMapa)),
                          const SizedBox(width: 8),
                          Expanded(child: _buildActionBtn('GPS', Icons.sync, const Color(0xFFFFE4E6), Colors.red.shade700, onTap: _actualizarGPS)),
                        ],
                      )
                    ],
                  ),
                ),
              const SizedBox(height: 24),

              if (_prestamoActivo!['estado'] == 'activo') ...[
                // Tarjeta Resumen Total a Liquidar Hoy
                _buildResumenPrestamo(),
                const SizedBox(height: 32),

                // Historial de Pagos
                const Text('HISTORIAL DE PAGOS', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey)),
                const SizedBox(height: 16),
                  ...cuotasMostrar.map((cuota) => _buildCuotaTile(cuota)),

                const SizedBox(height: 32),
              ] else ...[
                // Mensaje colorido para préstamos inactivos
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEFF6FF),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFFBFDBFE)),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: const BoxDecoration(color: Color(0xFF3B82F6), shape: BoxShape.circle),
                        child: const Icon(Icons.info_outline, color: Colors.white),
                      ),
                      const SizedBox(width: 16),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Préstamo Inactivo', style: TextStyle(color: Color(0xFF1E3A8A), fontWeight: FontWeight.bold, fontSize: 16)),
                            SizedBox(height: 4),
                            Text('El cliente no tiene un préstamo activo en este momento. Puede crear uno nuevo o renovar el crédito.', style: TextStyle(color: Color(0xFF1D4ED8), fontSize: 13)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 32),
              ],
              const Text('DOCUMENTOS DEL CLIENTE', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey)),
              const SizedBox(height: 16),
              _buildDocItem('Identificación (INE)', clienteInfo['foto_ine_url'], () => _cambiarDocumento('foto_ine_url', 'ine')),
              _buildDocItem('Comprobante de Domicilio', clienteInfo['foto_comprobante_url'], () => _cambiarDocumento('foto_comprobante_url', 'comprobante')),
              _buildDocItem('Contrato', clienteInfo['contrato_url'], () => _cambiarDocumento('contrato_url', 'contrato')),
              const SizedBox(height: 100), // Espacio para el boton flotante inferior
            ],
          ),
      floatingActionButton: (cuotasPagadas >= 17) 
        ? FloatingActionButton.extended(
            backgroundColor: const Color(0xFF09305A),
            foregroundColor: Colors.white,
            onPressed: () async {
              final montoCtrl = TextEditingController();
              final result = await showDialog<double>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('Renovar Crédito (Dueño)', style: TextStyle(color: Color(0xFF09305A), fontWeight: FontWeight.bold)),
                  content: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Ingresa el monto para el nuevo préstamo:'),
                      const SizedBox(height: 16),
                      TextField(
                        controller: montoCtrl,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: InputDecoration(
                          labelText: 'Monto Solicitado',
                          prefixText: '\$ ',
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ],
                  ),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
                    ElevatedButton(
                      onPressed: () {
                         final m = double.tryParse(montoCtrl.text);
                         if (m != null && m > 0) Navigator.pop(ctx, m);
                      },
                      style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF09305A), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                      child: const Text('Siguiente', style: TextStyle(color: Colors.white)),
                    ),
                  ],
                ),
              );

              if (result == null) return;
              
              setState(() => _isLoading = true);
              try {
                final cobradorId = _prestamoActivo!['cobrador_id'];
                
                final solRes = await Supabase.instance.client.from('solicitudes_renovacion').insert({
                  'prestamo_actual_id': _prestamoActivo!['id'],
                  'cliente_id': _prestamoActivo!['cliente_id'],
                  'cobrador_id': cobradorId,
                  'monto_solicitado': result,
                  'es_anticipada': _prestamoActivo!['estado'] != 'liquidado',
                }).select().single();
                
                if (mounted) {
                  // Navegamos a la pantalla de detalle de renovación para procesarla como Dueño
                  await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => 
                        // Importamos dinámicamente si no está en la cabecera
                        // Ya que esto es admin, usualmente está importado, si no, lo manejaremos
                        AdminRenovacionDetalleScreen(solicitud: solRes),
                    ),
                  );
                  await _fetchDetalles(); // Recargar datos al volver
                }
              } catch (e) {
                if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
              } finally {
                if (mounted) setState(() => _isLoading = false);
              }
            },
            icon: const Icon(Icons.autorenew, size: 20),
            label: const Text('Renovar Crédito', style: TextStyle(fontWeight: FontWeight.bold)),
          )
        : null,
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
    );
  }

  Widget _buildActionBtn(String label, IconData icon, Color bgColor, Color fgColor, {bool fullWidth = false, required VoidCallback onTap}) {
    return Container(
      height: 50,
      width: fullWidth ? double.infinity : null,
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: fgColor, size: 16),
              const SizedBox(width: 6),
              Text(label, style: TextStyle(color: fgColor, fontWeight: FontWeight.bold, fontSize: 13)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildResumenPrestamo() {
    double montoPagar = (_prestamoActivo!['monto_total_pagar'] ?? 0).toDouble();
    double faltante = (_prestamoActivo!['faltante_actual'] ?? 0).toDouble();
    double moratorios = (_prestamoActivo!['mora_acumulada'] ?? 0).toDouble();
    int atrasosConteo = (_prestamoActivo!['cuotas_atrasadas_conteo'] ?? 0) as int;
    double cuotaDiaria = (_prestamoActivo!['cuota_diaria'] ?? 0).toDouble();
    double montoAtrasos = atrasosConteo * cuotaDiaria;
    
    // Liquidación total real
    double liquidarHoy = faltante + moratorios;

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('TOTAL A LIQUIDAR HOY', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey)),
          const SizedBox(height: 8),
          Text(formatter.format(liquidarHoy), style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: Color(0xFF09305A))),
          const SizedBox(height: 24),
          _buildRowResumen('Total a Pagar', formatter.format(montoPagar), const Color(0xFF09305A), true),
          const SizedBox(height: 12),
          _buildRowResumen('Faltante', formatter.format(faltante), Colors.red.shade700, true),
          const SizedBox(height: 12),
          _buildRowResumen('Moratorios', formatter.format(moratorios), const Color(0xFF09305A), true),
          if (atrasosConteo > 0) ...[
            const SizedBox(height: 12),
            _buildRowResumen('Cuota atrasada', formatter.format(montoAtrasos), const Color(0xFFDC2626), true),
          ]
        ],
      ),
    );
  }

  Widget _buildRowResumen(String label, String value, Color valColor, bool isBold) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(color: Colors.grey, fontSize: 14)),
        Text(
          value,
          style: TextStyle(
            fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
            color: valColor,
            fontSize: 14
          ),
        ),
      ],
    );
  }

  Widget _buildCuotaTile(Map<String, dynamic> cuota) {
    int numCuota = cuota['numero_cuota'];
    double montoCuota = (cuota['monto_cuota'] ?? 0).toDouble();
    String estado = cuota['estado_pago'] ?? 'pendiente';
    String fechaStr = cuota['fecha_vencimiento'];
    
    // Parseo de fechas para determinar estado visual
    DateTime cuotaDate = DateTime.tryParse(fechaStr) ?? DateTime.now();
    DateTime hoy = DateTime.now();
    hoy = DateTime(hoy.year, hoy.month, hoy.day); // Normalizar a medianoche

    bool isPagada = estado == 'pagado';
    bool isVencida = estado == 'vencido';
    bool isAtrasada = estado == 'pendiente' && cuotaDate.isBefore(hoy);
    bool isHoy = estado == 'pendiente' && cuotaDate.isAtSameMomentAs(hoy);

    // Si la atención de hoy dice "no_pago", tratamos la cuota de hoy como "vencida" para que tenga la X roja.
    if (isHoy && _atencionHoy != null && _atencionHoy!['estado'] == 'no_pago') {
      isHoy = false;
      isVencida = true;
    }

    // Mantenemos colores solicitados, pero adaptados al layout de la imagen
    Color bgColor;
    Color fgColor;
    IconData? icon;
    String statusText;

    if (isPagada) {
      bgColor = const Color(0xFFDCFCE7); // Verde claro
      fgColor = Colors.green.shade700;
      icon = Icons.check;
      statusText = 'Pagado';
    } else if (isVencida) {
      bgColor = const Color(0xFFFFE4E6); // Rojo claro
      fgColor = Colors.red.shade700;
      icon = Icons.close;
      statusText = 'No Pagado';
    } else if (isAtrasada) {
      bgColor = const Color(0xFFFFE4E6); // Rojo claro
      fgColor = Colors.red.shade700;
      icon = Icons.priority_high;
      statusText = 'Atrasada';
    } else if (isHoy) {
      bgColor = const Color(0xFFFEF3C7); // Naranja claro
      fgColor = Colors.orange.shade800;
      icon = Icons.priority_high;
      statusText = 'Hoy';
    } else {
      bgColor = const Color(0xFFF3F4F6); // Gris claro (Futura)
      fgColor = Colors.grey.shade600;
      statusText = 'Futura';
    }

    // Formatear la fecha como dd/MM/yyyy
    String fDate = DateFormat('dd/MM/yyyy').format(cuotaDate);

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Circulo de Estatus
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: bgColor,
              shape: BoxShape.circle,
            ),
            child: icon != null 
                ? Icon(icon, color: fgColor, size: 20)
                : Center(child: Text('$numCuota', style: TextStyle(color: fgColor, fontWeight: FontWeight.bold, fontSize: 13))),
          ),
          const SizedBox(width: 16),
          // Textos
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Día $numCuota', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: isAtrasada ? fgColor : Colors.black87)),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Text('$statusText • $fDate', style: TextStyle(color: isAtrasada ? fgColor : Colors.grey, fontSize: 12)),
                    if (isPagada) ...[
                      const SizedBox(width: 6),
                      Icon(Icons.print_outlined, size: 14, color: Colors.grey.shade600),
                    ]
                  ],
                ),
              ],
            ),
          ),
          // Monto
          Text(formatter.format(montoCuota), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.black87)),
        ],
      ),
    );
  }

  Widget _buildDocItem(String label, String? url, VoidCallback onTap) {
    bool hasDoc = url != null && url.isNotEmpty;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: hasDoc ? const Color(0xFFDCFCE7) : const Color(0xFFF3F4F6),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(Icons.file_present_outlined, color: hasDoc ? Colors.green.shade700 : Colors.grey, size: 20),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(label, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black87)),
                      const SizedBox(height: 2),
                      Text(hasDoc ? 'Documento subido' : 'Pendiente', style: TextStyle(color: hasDoc ? Colors.green.shade700 : Colors.grey, fontSize: 12)),
                    ],
                  ),
                ),
                if (hasDoc)
                  IconButton(
                    icon: const Icon(Icons.open_in_new, color: Colors.blue, size: 20),
                    onPressed: () async {
                      final u = Uri.parse(url);
                      if (await canLaunchUrl(u)) await launchUrl(u);
                    },
                  ),
                const SizedBox(width: 8),
                Icon(Icons.camera_alt_outlined, color: const Color(0xFF09305A).withOpacity(hasDoc ? 0.3 : 1), size: 22),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
