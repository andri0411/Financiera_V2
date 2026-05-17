import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'agregar_cobrador.dart';
import 'cobrador_detalle_dueno.dart';

class CobradoresTab extends StatefulWidget {
  const CobradoresTab({super.key});

  @override
  State<CobradoresTab> createState() => _CobradoresTabState();
}

class _CobradoresTabState extends State<CobradoresTab> {
  bool _isLoading = true;
  List<dynamic> _cobradores = [];
  double _totalRecaudadoGlobal = 0;
  double _totalMetaGlobal = 0;

  @override
  void initState() {
    super.initState();
    _fetchCobradores();
  }

  Future<void> _fetchCobradores() async {
    setState(() => _isLoading = _cobradores.isEmpty);
    try {
      final hoyLocal = DateTime.now().toLocal();
      final hoyStr = '${hoyLocal.year.toString().padLeft(4, '0')}-${hoyLocal.month.toString().padLeft(2, '0')}-${hoyLocal.day.toString().padLeft(2, '0')}';
      final inicioLocal = DateTime(hoyLocal.year, hoyLocal.month, hoyLocal.day);
      final finLocal = inicioLocal.add(const Duration(days: 1));

      // 1. Obtener todos los cobradores activos
      final perfilesRes = await Supabase.instance.client
          .from('perfiles')
          .select('id, nombre_completo')
          .eq('rol', 'cobrador')
          .eq('activo', true);

      // 2. Obtener pagos registrados HOY por cualquier cobrador
      final pagosHoy = await Supabase.instance.client
          .from('pagos')
          .select('registrado_por, monto_recibido, monto_mora')
          .gte('fecha_pago', inicioLocal.toUtc().toIso8601String())
          .lt('fecha_pago', finLocal.toUtc().toIso8601String());

      // Agrupar pagos por cobrador
      final Map<String, double> recaudadoPorCobrador = {};
      final Map<String, double> moraPorCobrador = {};
      for (var pago in pagosHoy as List) {
        final id = pago['registrado_por'] as String?;
        if (id == null) continue;
        recaudadoPorCobrador[id] = (recaudadoPorCobrador[id] ?? 0) +
            ((pago['monto_recibido'] ?? 0) as num).toDouble();
        moraPorCobrador[id] = (moraPorCobrador[id] ?? 0) +
            ((pago['monto_mora'] ?? 0) as num).toDouble();
      }

      // 3. Obtener cuotas que vencen HOY de préstamos activos
      final cuotasHoy = await Supabase.instance.client
          .from('cuotas')
          .select('monto_cuota, prestamos!inner(cobrador_id, estado)')
          .eq('fecha_vencimiento', hoyStr)
          .neq('estado_pago', 'vencido')
          .eq('prestamos.estado', 'activo');

      // Agrupar meta por cobrador
      final Map<String, double> metaPorCobrador = {};
      for (var cuota in cuotasHoy as List) {
        final prestamo = cuota['prestamos'];
        if (prestamo == null) continue;
        final id = prestamo['cobrador_id'] as String?;
        if (id == null) continue;
        metaPorCobrador[id] = (metaPorCobrador[id] ?? 0) +
            ((cuota['monto_cuota'] ?? 0) as num).toDouble();
      }

      // Meta = max(programado hoy, total cobrado) para reflejar adelantos
      final List<Map<String, dynamic>> resultado = [];
      double recaudadoAcc = 0;
      double metaAcc = 0;

      for (var perfil in perfilesRes as List) {
        final id = perfil['id'] as String;
        final recaudado = recaudadoPorCobrador[id] ?? 0.0;
        final moraAdicional = moraPorCobrador[id] ?? 0.0;
        final metaScheduled = (metaPorCobrador[id] ?? 0.0) + moraAdicional;
        final meta = recaudado > metaScheduled ? recaudado : metaScheduled;
        recaudadoAcc += recaudado;
        metaAcc += meta;
        resultado.add({
          'id': id,
          'nombre_completo': perfil['nombre_completo'],
          'recaudado_hoy': recaudado,
          'meta_total_hoy': meta,
        });
      }

      setState(() {
        _cobradores = resultado;
        _totalRecaudadoGlobal = recaudadoAcc;
        _totalMetaGlobal = metaAcc;
        _isLoading = false;
      });
    } catch (e) {
      print('Error al obtener datos de cobradores: $e');
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final currencyFormatter = NumberFormat.currency(symbol: r'$', decimalDigits: 0);

    return Scaffold(
      backgroundColor: const Color(0xFFF9FAFB),
      body: Column(
        children: [
          // Header Principal Azul
          Container(
            width: double.infinity,
            decoration: const BoxDecoration(
              color: Color(0xFF09305A),
              borderRadius: BorderRadius.only(
                bottomLeft: Radius.circular(32),
                bottomRight: Radius.circular(32),
              ),
            ),
            padding: EdgeInsets.only(
              top: MediaQuery.of(context).padding.top + 20,
              left: 24,
              right: 24,
              bottom: 30,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Cobradores',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 28,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.5,
                      ),
                    ),
                    IconButton(
                      onPressed: _fetchCobradores,
                      icon: const Icon(Icons.refresh, color: Colors.white70),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Listado de Cobradores
          Expanded(
            child: RefreshIndicator(
              onRefresh: _fetchCobradores,
              color: const Color(0xFF09305A),
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _cobradores.isEmpty
                      ? ListView(
                          children: [
                            SizedBox(height: MediaQuery.of(context).size.height * 0.2),
                            const Center(
                              child: Text(
                                'No hay cobradores registrados.',
                                style: TextStyle(color: Color(0xFF6B7280), fontSize: 16),
                              ),
                            ),
                          ],
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
                          itemCount: _cobradores.length,
                          itemBuilder: (context, index) {
                            final cobrador = _cobradores[index];
                            final double recaudado = (cobrador['recaudado_hoy'] ?? 0).toDouble();
                            final double meta = (cobrador['meta_total_hoy'] ?? 0).toDouble();

                            double progreso = 0;
                            if (meta > 0) {
                              progreso = (recaudado / meta).clamp(0.0, 1.0);
                            }

                            return GestureDetector(
                              onTap: () async {
                                final result = await Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => CobradorDetalleDueno(
                                      cobradorId: cobrador['id'] as String,
                                      nombreCompleto: cobrador['nombre_completo'] ?? '',
                                    ),
                                  ),
                                );
                                if (result == true) _fetchCobradores();
                              },
                              child: Container(
                                margin: const EdgeInsets.only(bottom: 20),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(24),
                                  boxShadow: [
                                    BoxShadow(
                                      color: const Color(0xFF09305A).withOpacity(0.06),
                                      blurRadius: 20,
                                      offset: const Offset(0, 8),
                                    ),
                                  ],
                                ),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(24),
                                  child: Stack(
                                    children: [
                                      // Línea decorativa lateral
                                      Positioned(
                                        left: 0,
                                        top: 0,
                                        bottom: 0,
                                        width: 6,
                                        child: Container(color: const Color(0xFF09305A)),
                                      ),
                                      Padding(
                                        padding: const EdgeInsets.all(24),
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Row(
                                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                              children: [
                                                Expanded(
                                                  child: Text(
                                                    cobrador['nombre_completo'] ?? 'Sin Nombre',
                                                    style: const TextStyle(
                                                      fontSize: 20,
                                                      fontWeight: FontWeight.w800,
                                                      color: Color(0xFF09305A),
                                                      letterSpacing: -0.5,
                                                    ),
                                                  ),
                                                ),
                                                Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                                  decoration: BoxDecoration(
                                                    color: const Color(0xFFF3F4F6),
                                                    borderRadius: BorderRadius.circular(100),
                                                  ),
                                                  child: Text(
                                                    '${(progreso * 100).toStringAsFixed(0)}%',
                                                    style: const TextStyle(
                                                      fontSize: 12,
                                                      fontWeight: FontWeight.w700,
                                                      color: Color(0xFF09305A),
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                            const SizedBox(height: 24),
                                            Row(
                                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                              children: [
                                                const Text(
                                                  'RECAUDADO HOY',
                                                  style: TextStyle(
                                                    fontSize: 11,
                                                    fontWeight: FontWeight.w700,
                                                    color: Color(0xFF9CA3AF),
                                                    letterSpacing: 1.0,
                                                  ),
                                                ),
                                                Text(
                                                  '${currencyFormatter.format(recaudado)} / ${currencyFormatter.format(meta)}',
                                                  style: const TextStyle(
                                                    fontSize: 16,
                                                    fontWeight: FontWeight.w800,
                                                    color: Color(0xFF09305A),
                                                  ),
                                                ),
                                              ],
                                            ),
                                            const SizedBox(height: 12),
                                            // Barra de Progreso
                                            Stack(
                                              children: [
                                                Container(
                                                  height: 10,
                                                  width: double.infinity,
                                                  decoration: BoxDecoration(
                                                    color: const Color(0xFFF3F4F6),
                                                    borderRadius: BorderRadius.circular(10),
                                                  ),
                                                ),
                                                TweenAnimationBuilder<double>(
                                                  duration: const Duration(milliseconds: 800),
                                                  curve: Curves.easeOutCubic,
                                                  tween: Tween<double>(begin: 0, end: progreso),
                                                  builder: (context, value, _) => FractionallySizedBox(
                                                    widthFactor: value,
                                                    child: Container(
                                                      height: 10,
                                                      decoration: BoxDecoration(
                                                        gradient: const LinearGradient(
                                                          colors: [Color(0xFF22C55E), Color(0xFF16A34A)],
                                                        ),
                                                        borderRadius: BorderRadius.circular(10),
                                                        boxShadow: [
                                                          BoxShadow(
                                                            color: const Color(0xFF22C55E).withOpacity(0.3),
                                                            blurRadius: 8,
                                                            offset: const Offset(0, 2),
                                                          ),
                                                        ],
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                              ],
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
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: const Color(0xFF09305A),
        foregroundColor: Colors.white,
        onPressed: () async {
          final result = await Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const AgregarCobradorScreen()),
          );
          if (result == true) {
            _fetchCobradores();
          }
        },
        elevation: 4,
        icon: const Icon(Icons.add_rounded, size: 24),
        label: const Text(
          'NUEVO COBRADOR',
          style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: 0.5),
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
    );
  }
}
