import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';

class ConfigEditorPercentScreen extends StatefulWidget {
  final String title;
  final String hint;
  final String dbColumn;
  final String simulationLabel;

  const ConfigEditorPercentScreen({
    super.key,
    required this.title,
    required this.hint,
    required this.dbColumn,
    required this.simulationLabel,
  });

  @override
  State<ConfigEditorPercentScreen> createState() => _ConfigEditorPercentScreenState();
}

class _ConfigEditorPercentScreenState extends State<ConfigEditorPercentScreen> {
  final TextEditingController _valueController = TextEditingController();
  final formatter = NumberFormat.currency(locale: 'es_MX', symbol: '\$');
  bool _isLoading = true;
  double _currentValue = 0;

  @override
  void initState() {
    super.initState();
    _fetchConfig();
    _valueController.addListener(() {
      setState(() {
        _currentValue = double.tryParse(_valueController.text) ?? 0.0;
      });
    });
  }

  Future<void> _fetchConfig() async {
    try {
      final response = await Supabase.instance.client
          .from('configuracion')
          .select(widget.dbColumn)
          .eq('id', 1)
          .single();
      
      final val = (response[widget.dbColumn] as num?)?.toDouble() ?? 0.0;
      _valueController.text = val.toStringAsFixed(0); // Mostrar sin decimales si es entero
      setState(() {
        _isLoading = false;
        _currentValue = val;
      });
    } catch (e) {
      print('Error al obtener config: $e');
      setState(() => _isLoading = false);
    }
  }

  Future<void> _guardarCambios() async {
    setState(() => _isLoading = true);
    try {
      await Supabase.instance.client
          .from('configuracion')
          .update({widget.dbColumn: _currentValue})
          .eq('id', 1);
          
      if (mounted) {
        Navigator.pop(context, true);
      }
    } catch (e) {
      print('Error al guardar config: $e');
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
      setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    _valueController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Calculo de simulacion base 1000
    double prestamoBase = 1000.0;
    double resultadoSimulacion = prestamoBase * (_currentValue / 100);

    return Scaffold(
      backgroundColor: const Color(0xFFF3F4F6),
      appBar: AppBar(
        backgroundColor: const Color(0xFF09305A),
        foregroundColor: Colors.white,
        title: Text(widget.title),
        elevation: 0,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(24),
              children: [
                Text(
                  widget.hint,
                  style: const TextStyle(color: Colors.grey, fontSize: 16),
                ),
                const SizedBox(height: 24),
                const Text('Valor Nuevo', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF09305A))),
                const SizedBox(height: 8),
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _valueController,
                          keyboardType: TextInputType.number,
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
                          decoration: const InputDecoration(
                            border: InputBorder.none,
                            contentPadding: EdgeInsets.symmetric(vertical: 20),
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF3F4F6),
                          borderRadius: const BorderRadius.only(
                            topRight: Radius.circular(12),
                            bottomRight: Radius.circular(12),
                          ),
                          border: Border.all(color: const Color(0xFFE5E7EB)),
                        ),
                        child: const Text('%', style: TextStyle(fontSize: 24, color: Colors.grey)),
                      )
                    ],
                  ),
                ),
                const SizedBox(height: 32),
                const Text('Simulación (Base \$100.00)', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)), // Nota dice base 100 pero en UI es base 1000
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: const Color(0xFFECFDF5), // Verde muy muy claro
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFD1FAE5)),
                  ),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Préstamo de \$1,000.00', style: TextStyle(color: Colors.black54, fontSize: 16)),
                          const SizedBox(),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(widget.simulationLabel, style: const TextStyle(color: Colors.black54, fontSize: 16)),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: const Color(0xFFD1FAE5), // Verde claro
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              (widget.dbColumn == 'penalizacion_incumplimiento_30d' || widget.dbColumn == 'porcentaje_mora_diaria')
                                ? '+${formatter.format(resultadoSimulacion)}'
                                : formatter.format(resultadoSimulacion),
                              style: const TextStyle(color: Color(0xFF065F46), fontWeight: FontWeight.bold),
                            ),
                          ),
                        ],
                      )
                    ],
                  ),
                ),
                const SizedBox(height: 40),
                ElevatedButton(
                  onPressed: _guardarCambios,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF09305A),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text('Guardar Cambios', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
    );
  }
}
