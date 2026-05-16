import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'package:blue_thermal_printer/blue_thermal_printer.dart';
import 'package:flutter/services.dart';

class ConfigTicketScreen extends StatefulWidget {
  const ConfigTicketScreen({super.key});

  @override
  State<ConfigTicketScreen> createState() => _ConfigTicketScreenState();
}

class _ConfigTicketScreenState extends State<ConfigTicketScreen> {
  final TextEditingController _headerController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _footerController = TextEditingController();

  bool _isLoading = true;

  // Variables para la impresora Bluetooth
  BlueThermalPrinter bluetooth = BlueThermalPrinter.instance;
  List<BluetoothDevice> _devices = [];
  BluetoothDevice? _device;
  bool _connected = false;

  @override
  void initState() {
    super.initState();
    _fetchTicketConfig();
    _initBluetooth();
    
    // Listeners for real-time preview
    _headerController.addListener(() => setState(() {}));
    _phoneController.addListener(() => setState(() {}));
    _footerController.addListener(() => setState(() {}));
  }

  Future<void> _initBluetooth() async {
    bool? isConnected = await bluetooth.isConnected;
    List<BluetoothDevice> devices = [];
    try {
      devices = await bluetooth.getBondedDevices();
    } on PlatformException {
      // Ignorar error si no es posible obtener los dispositivos
    }
    if (!mounted) return;
    setState(() {
      _devices = devices;
      _connected = isConnected ?? false;
    });
  }

  void _showBluetoothDialog() {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Impresoras Vinculadas'),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: _devices.isEmpty ? 1 : _devices.length,
              itemBuilder: (context, index) {
                if (_devices.isEmpty) {
                  return const Text('No hay dispositivos bluetooth vinculados. Por favor vincule la impresora desde la configuración de su teléfono primero.');
                }
                final device = _devices[index];
                return ListTile(
                  leading: const Icon(Icons.print),
                  title: Text(device.name ?? 'Desconocido'),
                  subtitle: Text(device.address ?? ''),
                  onTap: () async {
                    Navigator.pop(context);
                    await bluetooth.connect(device).catchError((e) {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error de conexión: $e')));
                    });
                    bool? isConnected = await bluetooth.isConnected;
                    setState(() {
                      _device = device;
                      _connected = isConnected ?? false;
                    });
                    if (_connected) {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Conectado a ${device.name}')));
                    }
                  },
                );
              },
            ),
          ),
          actions: [
             if (_connected)
               TextButton(
                 onPressed: () async {
                   await bluetooth.disconnect();
                   setState(() => _connected = false);
                   Navigator.pop(context);
                 },
                 child: const Text('Desconectar', style: TextStyle(color: Colors.red)),
               ),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cerrar'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _fetchTicketConfig() async {
    try {
      final res = await Supabase.instance.client
          .from('configuracion')
          .select('ticket_header, ticket_phone, ticket_footer')
          .eq('id', 1)
          .single();
          
      _headerController.text = res['ticket_header'] ?? 'FINANCIERA REGIONAL';
      _phoneController.text = res['ticket_phone'] ?? '999-107-9110';
      _footerController.text = res['ticket_footer'] ?? 'Gracias por su Puntualidad';
      
      setState(() {
        _isLoading = false;
      });
    } catch (e) {
      print('Error al cargar diseño de ticket: $e');
      setState(() => _isLoading = false);
    }
  }

  Future<void> _saveConfig() async {
    setState(() => _isLoading = true);
    try {
      await Supabase.instance.client
          .from('configuracion')
          .update({
            'ticket_header': _headerController.text,
            'ticket_phone': _phoneController.text,
            'ticket_footer': _footerController.text,
          })
          .eq('id', 1);
          
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Diseño guardado correctamente')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al guardar: $e')),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    _headerController.dispose();
    _phoneController.dispose();
    _footerController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0F4F8),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF0F4F8),
        foregroundColor: const Color(0xFF09305A),
        elevation: 0,
        title: const Text('Diseño de Ticket', style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            icon: Icon(Icons.bluetooth, color: _connected ? Colors.green : Colors.blue),
            tooltip: 'Conectar Impresora',
            onPressed: _showBluetoothDialog,
          ),
          TextButton.icon(
            icon: const Icon(Icons.save, color: Colors.blue),
            label: const Text('Guardar', style: TextStyle(color: Colors.blue)),
            onPressed: _saveConfig,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Previsualización del ticket en tiempo real
                        Container(
                          padding: const EdgeInsets.all(24),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFDFBF2), // Color papel crema claro
                            borderRadius: BorderRadius.circular(8),
                            boxShadow: [
                              BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 5))
                            ],
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Text(
                                _headerController.text.toUpperCase(),
                                textAlign: TextAlign.center,
                                style: const TextStyle(fontFamily: 'Courier', fontWeight: FontWeight.bold, fontSize: 18),
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'TEL ${_phoneController.text}',
                                textAlign: TextAlign.center,
                                style: const TextStyle(fontFamily: 'Courier', fontWeight: FontWeight.bold, fontSize: 14),
                              ),
                              const SizedBox(height: 24),
                              const Align(
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  'FECHA: 11/05/2026      HORA: 08:57\nCLIENTE: GINA JANET POO L HERRERA\nPAGO DIARIO: \$210.0 PLAZO 40\nTERMINO DEL CREDITO: 29/04/2026\nLE ATENDIO: JUAN PEREZ',
                                  style: TextStyle(fontFamily: 'Courier', fontSize: 13, height: 1.5, fontWeight: FontWeight.bold),
                                ),
                              ),
                              const SizedBox(height: 16),
                              const Text('. . . . . . . . . . . . . . . . .', style: TextStyle(fontFamily: 'Courier', fontWeight: FontWeight.bold)),
                              const Text('DETALLES DEL PAGO', style: TextStyle(fontFamily: 'Courier', fontWeight: FontWeight.bold, fontSize: 14)),
                              const Text('. . . . . . . . . . . . . . . . .', style: TextStyle(fontFamily: 'Courier', fontWeight: FontWeight.bold)),
                              const SizedBox(height: 16),
                              const Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text('PAGOS REALIZADOS:', style: TextStyle(fontFamily: 'Courier', fontWeight: FontWeight.bold)),
                                  Text('1 PAGOS', style: TextStyle(fontFamily: 'Courier', fontWeight: FontWeight.bold)),
                                ],
                              ),
                              const SizedBox(height: 8),
                              const Align(
                                alignment: Alignment.centerLeft,
                                child: Text('USTED ESTA EN SU PAGO:\n#15 DE 40 PAGOS', style: TextStyle(fontFamily: 'Courier', fontWeight: FontWeight.bold, height: 1.5)),
                              ),
                              const SizedBox(height: 8),
                              const Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text('IMPORTE:', style: TextStyle(fontFamily: 'Courier', fontWeight: FontWeight.bold)),
                                  Text('\$210.00', style: TextStyle(fontFamily: 'Courier', fontWeight: FontWeight.bold)),
                                ],
                              ),
                              const SizedBox(height: 16),
                              const Text('GRACIAS POR SU PAGO!!', style: TextStyle(fontFamily: 'Courier', fontWeight: FontWeight.bold)),
                              const SizedBox(height: 16),
                              const Text('. . . . . . . . . . . . . . . . .', style: TextStyle(fontFamily: 'Courier', fontWeight: FontWeight.bold)),
                              const Text('SALDO', style: TextStyle(fontFamily: 'Courier', fontWeight: FontWeight.bold, fontSize: 14)),
                              const Text('. . . . . . . . . . . . . . . . .', style: TextStyle(fontFamily: 'Courier', fontWeight: FontWeight.bold)),
                              const SizedBox(height: 16),
                              const Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text('DEBE MORATORIAS:', style: TextStyle(fontFamily: 'Courier', fontWeight: FontWeight.bold)), Text('\$50.00', style: TextStyle(fontFamily: 'Courier', fontWeight: FontWeight.bold))]),
                              const SizedBox(height: 8),
                              const Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text('PAGOS ATRASADOS:', style: TextStyle(fontFamily: 'Courier', fontWeight: FontWeight.bold)), Text('\$0.00', style: TextStyle(fontFamily: 'Courier', fontWeight: FontWeight.bold))]),
                              const SizedBox(height: 8),
                              const Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text('PENALIZACION GRAVE', style: TextStyle(fontFamily: 'Courier', fontWeight: FontWeight.bold)), Text('NO', style: TextStyle(fontFamily: 'Courier', fontWeight: FontWeight.bold))]),
                              const SizedBox(height: 8),
                              const Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text('PAGOS RESTANTES:', style: TextStyle(fontFamily: 'Courier', fontWeight: FontWeight.bold)), Text('25 PAGOS', style: TextStyle(fontFamily: 'Courier', fontWeight: FontWeight.bold))]),
                              const SizedBox(height: 8),
                              const Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text('FALTA LIQUIDAR:', style: TextStyle(fontFamily: 'Courier', fontWeight: FontWeight.bold)), Text('\$5,250.00', style: TextStyle(fontFamily: 'Courier', fontWeight: FontWeight.bold))]),
                              const SizedBox(height: 24),
                              Text(
                                _footerController.text,
                                textAlign: TextAlign.center,
                                style: const TextStyle(fontFamily: 'Courier', fontWeight: FontWeight.bold, fontSize: 14),
                              )
                            ],
                          ),
                        ),
                        const SizedBox(height: 32),
                        const Text('Configuración Manual', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF09305A))),
                        const SizedBox(height: 16),
                        _buildTextField('Encabezado del Ticket', _headerController),
                        const SizedBox(height: 12),
                        _buildTextField('Teléfono', _phoneController),
                        const SizedBox(height: 12),
                        _buildTextField('Pie del Ticket', _footerController, maxLines: 3),
                        const SizedBox(height: 24),
                      ],
                    ),
                  ),
                ),
                // Botón Imprimir Muestra Fijo Abajo
                Container(
                  padding: const EdgeInsets.all(16),
                  color: const Color(0xFFF0F4F8),
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _connected ? const Color(0xFF0A1B2F) : Colors.grey,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    icon: const Icon(Icons.print),
                    label: Text(_connected ? 'Imprimir Muestra' : 'Conecte impresora primero', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    onPressed: () {
                      if (!_connected) {
                        _showBluetoothDialog();
                        return;
                      }
                      bluetooth.printCustom(_headerController.text.toUpperCase(), 2, 1);
                      bluetooth.printCustom('TEL ${_phoneController.text}', 1, 1);
                      bluetooth.printNewLine();
                      bluetooth.printCustom('ESTA ES UNA PRUEBA DE IMPRESION DEL TICKET PARA COMPROBAR CONEXION', 1, 1);
                      bluetooth.printNewLine();
                      bluetooth.printCustom(_footerController.text, 1, 1);
                      bluetooth.printNewLine();
                      bluetooth.printNewLine();
                      bluetooth.paperCut();
                    },
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildTextField(String label, TextEditingController controller, {int maxLines = 1}) {
    return TextField(
      controller: controller,
      maxLines: maxLines,
      decoration: InputDecoration(
        labelText: label,
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }
}

