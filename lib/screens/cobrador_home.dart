import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';
import 'cobrador_cliente_detalle.dart';

class CobradorHomeScreen extends StatefulWidget {
  const CobradorHomeScreen({super.key});

  @override
  State<CobradorHomeScreen> createState() => _CobradorHomeScreenState();
}

class _CobradorHomeScreenState extends State<CobradorHomeScreen> {
  final formatter = NumberFormat.currency(locale: 'es_MX', symbol: '\$');
  bool _isLoading = true;
  String _nombreCobrador = '';
  double _cobrado = 0.0;
  double _pendiente = 0.0;
  List<Map<String, dynamic>> _clientesEnRuta = [];
  Position? _currentPosition;

  @override
  void initState() {
    super.initState();
    _fetchData();
  }

  Future<void> _fetchData({bool showLoading = true}) async {
    if (showLoading) {
      setState(() { _isLoading = true; });
    }

    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId == null) throw Exception('No hay usuario autenticado');

      final String hoyStr = DateTime.now().toIso8601String().split('T')[0];
      final DateTime hoyDate = DateTime.parse(hoyStr);

      // 1. Obtener perfil
      final perfilRes = await Supabase.instance.client
          .from('perfiles')
          .select('nombre_completo')
          .eq('id', userId)
          .maybeSingle();
      
      String nombreCompleto = perfilRes?['nombre_completo'] ?? '';
      _nombreCobrador = nombreCompleto.split(' ').first;

      // 2. Calcular "Cobrado hoy": suma de todos los pagos de hoy (hora local → UTC)
      final hoyLocal = DateTime.now().toLocal();
      final inicioLocal = DateTime(hoyLocal.year, hoyLocal.month, hoyLocal.day);
      final finLocal = inicioLocal.add(const Duration(days: 1));
      final pagosHoy = await Supabase.instance.client
          .from('pagos')
          .select('monto_recibido')
          .eq('registrado_por', userId)
          .gte('fecha_pago', inicioLocal.toUtc().toIso8601String())
          .lt('fecha_pago', finLocal.toUtc().toIso8601String());

      _cobrado = (pagosHoy as List).fold(0.0, (sum, p) => sum + ((p['monto_recibido'] ?? 0) as num).toDouble());

      // 3. Obtener préstamos activos asignados a este cobrador
      final prestamosActivos = await Supabase.instance.client
          .from('prestamos')
          .select('*, clientes(*)')
          .eq('cobrador_id', userId)
          .eq('estado', 'activo');

      // 4. Obtener atenciones de hoy para este cobrador
      final atencionesHoy = await Supabase.instance.client
          .from('atencion_diaria')
          .select()
          .eq('cobrador_id', userId)
          .eq('fecha', hoyStr);

      // 5. Obtener cuotas de todos los préstamos activos del cobrador (pendientes y pagadas)
      final prestamoIds = (prestamosActivos as List).map((p) => p['id'] as String).toList();
      Map<String, DateTime> proximaCuotaPorPrestamo = {};
      Map<String, int> cuotasPagadasPorPrestamo = {};

      if (prestamoIds.isNotEmpty) {
        // Cuotas pendientes → para saber cuándo vence la próxima
        final cuotasPendRes = await Supabase.instance.client
            .from('cuotas')
            .select('prestamo_id, fecha_vencimiento')
            .inFilter('prestamo_id', prestamoIds)
            .eq('estado_pago', 'pendiente')
            .order('fecha_vencimiento', ascending: true);
        for (var c in cuotasPendRes as List) {
          final pid = c['prestamo_id'] as String;
          final fecha = DateTime.tryParse(c['fecha_vencimiento'] ?? '');
          if (fecha != null && !proximaCuotaPorPrestamo.containsKey(pid)) {
            proximaCuotaPorPrestamo[pid] = fecha;
          }
        }
        // Cuotas pagadas → para detectar adelantos
        final cuotasPagRes = await Supabase.instance.client
            .from('cuotas')
            .select('prestamo_id')
            .inFilter('prestamo_id', prestamoIds)
            .eq('estado_pago', 'pagado');
        for (var c in cuotasPagRes as List) {
          final pid = c['prestamo_id'] as String;
          cuotasPagadasPorPrestamo[pid] = (cuotasPagadasPorPrestamo[pid] ?? 0) + 1;
        }
      }

      // Mapa para acceso rápido a las atenciones
      final atencionesMap = {
        for (var a in atencionesHoy) a['cliente_id']: a['estado']
      };

      // 6. Filtrar clientes en ruta:
      //    - fecha_inicio ya pasó
      //    - sin atención hoy (cobrado/no_pago)
      //    - tiene cuota vencida HOY o antes, O tiene adelantos que cubren hoy
      List<Map<String, dynamic>> clientesFiltrados = [];
      for (var prestamo in prestamosActivos) {
        final cliente = prestamo['clientes'];
        if (cliente == null) continue;

        final fechaInicioStr = prestamo['fecha_inicio'];
        if (fechaInicioStr != null) {
          final fechaInicio = DateTime.tryParse(fechaInicioStr);
          if (fechaInicio != null && fechaInicio.isAfter(hoyDate)) continue;
        }

        final prestamoId = prestamo['id'] as String;
        final proximaCuota = proximaCuotaPorPrestamo[prestamoId];
        final pagadas = cuotasPagadasPorPrestamo[prestamoId] ?? 0;

        // Calcular si tiene adelantos cubriendo hoy
        bool tieneAdelantos = false;
        if (fechaInicioStr != null) {
          final fechaInicio = DateTime.tryParse(fechaInicioStr);
          if (fechaInicio != null) {
            final diasTranscurridos = hoyDate.difference(
              DateTime(fechaInicio.year, fechaInicio.month, fechaInicio.day)
            ).inDays;
            tieneAdelantos = pagadas > diasTranscurridos;
          }
        }

        // Incluir si: tiene cuota vencida hoy/antes O tiene adelantos activos
        final cuotaVenceHoyOAntes = proximaCuota != null && !proximaCuota.isAfter(hoyDate);
        if (!cuotaVenceHoyOAntes && !tieneAdelantos) continue;

        final estadoAtencion = atencionesMap[cliente['id']];
        if (estadoAtencion == null || estadoAtencion == 'pendiente') {
          double montoMostrar = (prestamo['cuota_diaria'] ?? 0).toDouble();
          clientesFiltrados.add({
            'cliente': cliente,
            'prestamo': prestamo,
            'monto_pendiente': montoMostrar,
            'tiene_adelantos': tieneAdelantos,
            'distancia': double.maxFinite,
          });
        }
      }

      _clientesEnRuta = clientesFiltrados;

      // Pendiente = cuotas de clientes sin atender hoy (solo los que tienen cuota real hoy)
      _pendiente = clientesFiltrados
          .where((c) => !(c['tiene_adelantos'] as bool))
          .fold(0.0, (sum, c) => sum + (c['monto_pendiente'] as double));

      // 7. Intentar obtener GPS y ordenar
      await _ordenarPorUbicacion();


    } catch (e) {
      print('Error fetching data: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al cargar datos: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _ordenarPorUbicacion() async {
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.whileInUse || permission == LocationPermission.always) {
        _currentPosition = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
        
        // Calcular distancia para cada cliente
        for (var c in _clientesEnRuta) {
          final clienteData = c['cliente'];
          if (clienteData['latitud'] != null && clienteData['longitud'] != null) {
            double dist = Geolocator.distanceBetween(
              _currentPosition!.latitude, 
              _currentPosition!.longitude, 
              clienteData['latitud'].toDouble(), 
              clienteData['longitud'].toDouble()
            );
            c['distancia'] = dist;
          }
        }

        // Ordenar por distancia (los que no tienen GPS quedan al final con double.maxFinite)
        _clientesEnRuta.sort((a, b) => (a['distancia'] as double).compareTo(b['distancia'] as double));
      }
    } catch (e) {
      print("Error obteniendo ubicación: $e");
    }

    if (mounted) setState(() {});
  }

  Future<void> _abrirMapa(Map<String, dynamic> cliente) async {
    final lat = cliente['latitud'];
    final lng = cliente['longitud'];

    if (lat != null && lng != null) {
      final Uri url = Uri.parse("https://www.google.com/maps/dir/?api=1&destination=$lat,$lng");
      try {
        await launchUrl(url, mode: LaunchMode.externalApplication);
        return;
      } catch (e) {
        print("Error abriendo mapa: $e");
      }
    }

    final d = cliente['direccion'];
    if (d != null && d.toString().trim().isNotEmpty) {
      final Uri url = Uri.parse("https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent(d)}");
      try {
        await launchUrl(url, mode: LaunchMode.externalApplication);
        return;
      } catch (e) {
        print("Error abriendo mapa con dirección: $e");
      }
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ubicación no disponible para este cliente')),
      );
    }
  }

  Future<void> _cerrarSesion() async {
    await Supabase.instance.client.auth.signOut();
    if (mounted) {
      Navigator.pushReplacementNamed(context, '/'); // Asegúrate de tener esta ruta o usa el import
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        backgroundColor: Color(0xFFF3F4F6),
        body: Center(child: CircularProgressIndicator(color: Color(0xFF09305A))),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF3F4F6),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(24.0),
              decoration: const BoxDecoration(
                color: Color(0xFF09305A),
                borderRadius: BorderRadius.only(
                  bottomLeft: Radius.circular(32),
                  bottomRight: Radius.circular(32),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Hola $_nombreCobrador',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'MI RUTA HOY',
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.2,
                        ),
                      ),
                      OutlinedButton.icon(
                        onPressed: _fetchData, // Re-ordenar/refrescar
                        icon: const Icon(Icons.near_me_outlined, size: 16, color: Colors.white),
                        label: const Text('Ordenar ruta', style: TextStyle(color: Colors.white, fontSize: 12)),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: Colors.white30),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                          ),
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  
                  // Cobrado
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Cobrado',
                        style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w500),
                      ),
                      Text(
                        formatter.format(_cobrado),
                        style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Container(
                    height: 4,
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 16),
                  
                  // Pendiente
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Pendiente',
                        style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w500),
                      ),
                      Text(
                        formatter.format(_pendiente),
                        style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  // Línea de progreso color cyan
                  Container(
                    height: 6,
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: const Color(0xFF06B6D4), // Teal/Cyan de la imagen
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ],
              ),
            ),
            
            // Título de la lista
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'CLIENTES EN RUTA',
                        style: TextStyle(
                          color: Colors.grey,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.2,
                        ),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Pendientes',
                        style: TextStyle(
                          color: Color(0xFF09305A),
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  Text(
                    '${_clientesEnRuta.length}',
                    style: const TextStyle(
                      color: Color(0xFF09305A),
                      fontSize: 28,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            
            // Lista de Clientes
            Expanded(
              child: _clientesEnRuta.isEmpty
                ? const Center(
                    child: Text(
                      'No hay clientes pendientes en tu ruta hoy.',
                      style: TextStyle(color: Colors.grey, fontSize: 16),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    itemCount: _clientesEnRuta.length,
                    itemBuilder: (context, index) {
                      final item = _clientesEnRuta[index];
                      return _buildClienteCard(index + 1, item);
                    },
                  ),
            ),
          ],
        ),
      ),
      
    );
  }

  Widget _buildClienteCard(int numero, Map<String, dynamic> item) {
    final cliente = item['cliente'] as Map<String, dynamic>;
    final montoPendiente = item['monto_pendiente'] as double;
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Indicador de número y línea vertical
            Column(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: const BoxDecoration(
                    color: Color(0xFF09305A),
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    '$numero',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                ),
                Expanded(
                  child: Container(
                    width: 2,
                    margin: const EdgeInsets.symmetric(vertical: 8),
                    color: Colors.grey.shade300,
                  ),
                ),
              ],
            ),
            const SizedBox(width: 16),
            // Tarjeta principal
            Expanded(
              child: GestureDetector(
                onTap: () async {
                  final resultado = await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => CobradorClienteDetalleScreen(
                        cliente: cliente,
                        prestamo: item['prestamo'],
                      ),
                    ),
                  );
                  if (resultado == 'pasar') {
                    setState(() {
                      _clientesEnRuta.remove(item);
                      _clientesEnRuta.add(item);
                    });
                  } else if (resultado == 'cobrado' || resultado == 'no_pago') {
                    // Eliminación instantánea de la UI
                    final cuotaCliente = item['monto_pendiente'] as double;
                    setState(() {
                      _clientesEnRuta.remove(item);
                      if (resultado == 'cobrado') _cobrado += cuotaCliente;
                      // Recalcular pendiente con la lista actualizada
                      _pendiente = _clientesEnRuta.fold(0.0, (s, c) => s + (c['monto_pendiente'] as double));
                    });
                    // Refrescar en background sin bloquear UI
                    _fetchData(showLoading: false);
                  }
                },
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.grey.shade200),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.02),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              cliente['nombre_completo'] ?? 'Sin nombre',
                              style: const TextStyle(
                                color: Color(0xFF09305A),
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 6),
                            const Text(
                              'PENDIENTE',
                              style: TextStyle(
                                color: Colors.grey,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 1.0,
                              ),
                            ),
                            Text(
                              formatter.format(montoPendiente),
                              style: const TextStyle(
                                color: Color(0xFF09305A),
                                fontSize: 18,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      // Botón Mapa
                      InkWell(
                        onTap: () => _abrirMapa(cliente),
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFFE0F2FE), // Light blue
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(
                            Icons.map_outlined,
                            color: Color(0xFF09305A),
                            size: 24,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
