import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';

class ConfigDescansoScreen extends StatefulWidget {
  const ConfigDescansoScreen({super.key});

  @override
  State<ConfigDescansoScreen> createState() => _ConfigDescansoScreenState();
}

class _ConfigDescansoScreenState extends State<ConfigDescansoScreen> {
  bool _isLoading = true;
  List<int> _diasSemanales = [];
  List<Map<String, dynamic>> _vacaciones = [];

  final List<String> _diasNombres = ['Domingo', 'Lunes', 'Martes', 'Miércoles', 'Jueves', 'Viernes', 'Sábado'];

  @override
  void initState() {
    super.initState();
    _fetchDescansos();
  }

  Future<void> _fetchDescansos() async {
    setState(() => _isLoading = true);
    try {
      // Fetch dias descanso semanal from configuracion (id=1)
      final resConfig = await Supabase.instance.client
          .from('configuracion')
          .select('dias_descanso_semanal')
          .eq('id', 1)
          .single();
      
      List<dynamic> rawDias = resConfig['dias_descanso_semanal'] ?? [0];
      _diasSemanales = rawDias.map((e) => e as int).toList();

      // Fetch descansos programados (vacaciones o días feriados)
      final resVacaciones = await Supabase.instance.client
          .from('descansos_programados')
          .select()
          .order('fecha_inicio', ascending: true);
          
      _vacaciones = List<Map<String, dynamic>>.from(resVacaciones);

      setState(() => _isLoading = false);
    } catch (e) {
      print(e);
      setState(() => _isLoading = false);
    }
  }

  Future<void> _toggleDiaSemanal(int dayIndex, bool selected) async {
    setState(() {
      if (selected && !_diasSemanales.contains(dayIndex)) {
        _diasSemanales.add(dayIndex);
      } else if (!selected) {
        _diasSemanales.remove(dayIndex);
      }
    });

    try {
      await Supabase.instance.client
          .from('configuracion')
          .update({'dias_descanso_semanal': _diasSemanales})
          .eq('id', 1);
      await Supabase.instance.client.rpc('fn_recalcular_todas_las_cuotas');
    } catch (e) {
      print('Error update: $e');
    }
  }

  Future<void> _addVacaciones(DateTime start, DateTime end, String motivo) async {
    try {
      await Supabase.instance.client.from('descansos_programados').insert({
        'fecha_inicio': DateFormat('yyyy-MM-dd').format(start),
        'fecha_fin': DateFormat('yyyy-MM-dd').format(end),
        'motivo': motivo,
      });
      await Supabase.instance.client.rpc('fn_recalcular_todas_las_cuotas');
      _fetchDescansos();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }
  
  Future<void> _deleteVacacion(String id) async {
    try {
      await Supabase.instance.client.from('descansos_programados').delete().eq('id', id);
      await Supabase.instance.client.rpc('fn_recalcular_todas_las_cuotas');
      _fetchDescansos();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  void _showAddVacacionDialog() {
    DateTime? startDate;
    DateTime? endDate;
    final motivoCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Agregar Feriado/Vacaciones'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: motivoCtrl,
                    decoration: const InputDecoration(labelText: 'Motivo (ej: Navidad)'),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      const Text('Inicio: '),
                      TextButton(
                        onPressed: () async {
                          final d = await showDatePicker(context: context, initialDate: DateTime.now(), firstDate: DateTime.now(), lastDate: DateTime(2100));
                          if (d != null) setDialogState(() => startDate = d);
                        },
                        child: Text(startDate != null ? DateFormat('yyyy-MM-dd').format(startDate!) : 'Seleccionar'),
                      )
                    ],
                  ),
                  Row(
                    children: [
                      const Text('Fin:    '),
                      TextButton(
                        onPressed: () async {
                          final d = await showDatePicker(context: context, initialDate: startDate ?? DateTime.now(), firstDate: startDate ?? DateTime.now(), lastDate: DateTime(2100));
                          if (d != null) setDialogState(() => endDate = d);
                        },
                        child: Text(endDate != null ? DateFormat('yyyy-MM-dd').format(endDate!) : 'Seleccionar'),
                      )
                    ],
                  )
                ],
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
                ElevatedButton(
                  onPressed: () {
                    if (startDate != null && endDate != null && motivoCtrl.text.isNotEmpty) {
                      Navigator.pop(ctx);
                      _addVacaciones(startDate!, endDate!, motivoCtrl.text);
                    }
                  },
                  child: const Text('Agregar'),
                )
              ],
            );
          }
        );
      }
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Días de Descanso'),
        backgroundColor: const Color(0xFF09305A),
        foregroundColor: Colors.white,
      ),
      body: _isLoading 
        ? const Center(child: CircularProgressIndicator()) 
        : ListView(
            padding: const EdgeInsets.all(24),
            children: [
              const Text('Días de Descanso Semanal', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF09305A))),
              const Text('Se omitirá el cobro de moratorias en estos días.', style: TextStyle(color: Colors.grey)),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: List.generate(7, (index) {
                  final isSelected = _diasSemanales.contains(index);
                  return FilterChip(
                    label: Text(_diasNombres[index]),
                    selected: isSelected,
                    onSelected: (bool selected) => _toggleDiaSemanal(index, selected),
                    selectedColor: const Color(0xFFD1FAE5),
                    checkmarkColor: const Color(0xFF065F46),
                  );
                }),
              ),
              const Divider(height: 48),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Días Feriados / Vacaciones', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF09305A))),
                  IconButton(
                    icon: const Icon(Icons.add_circle, color: Color(0xFF09305A), size: 32),
                    onPressed: _showAddVacacionDialog,
                  )
                ],
              ),
              const SizedBox(height: 8),
              if (_vacaciones.isEmpty) 
                const Text('No hay vacaciones programadas.', style: TextStyle(color: Colors.grey))
              else
                ..._vacaciones.map((v) => Card(
                  child: ListTile(
                    title: Text(v['motivo']),
                    subtitle: Text('Del ${v['fecha_inicio']} al ${v['fecha_fin']}'),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete, color: Colors.red),
                      onPressed: () => _deleteVacacion(v['id']),
                    ),
                  ),
                )).toList()
            ],
          ),
    );
  }
}
