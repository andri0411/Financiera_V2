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

  void _openBluetoothScreen() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => BluetoothPrinterScreen(
          bluetooth: bluetooth,
          initialDevices: _devices,
          connectedDevice: _connected ? _device : null,
          onDeviceConnected: (device) {
            setState(() {
              _device = device;
              _connected = true;
            });
          },
          onDeviceDisconnected: () {
            setState(() {
              _device = null;
              _connected = false;
            });
          },
        ),
      ),
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
            onPressed: _openBluetoothScreen,
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
                                  'FECHA: 11/05/26   HORA: 08:57\nCLIENTE: GINA JANET POO\nPAGO DIARIO:\$210.0 PLAZO 40\nVENCIMIENTO: 29/04/2026\nLE ATENDIO: JUAN PEREZ',
                                  style: TextStyle(fontFamily: 'Courier', fontSize: 13, height: 1.5, fontWeight: FontWeight.bold),
                                ),
                              ),
                              const SizedBox(height: 4),
                              const Text('--------------------------------', style: TextStyle(fontFamily: 'Courier', fontWeight: FontWeight.bold)),
                              const Text('DETALLES DEL PAGO', style: TextStyle(fontFamily: 'Courier', fontWeight: FontWeight.bold, fontSize: 14)),
                              const Text('--------------------------------', style: TextStyle(fontFamily: 'Courier', fontWeight: FontWeight.bold)),
                              const SizedBox(height: 16),
                              const Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text('PAGOS REALIZADOS:', style: TextStyle(fontFamily: 'Courier', fontWeight: FontWeight.bold)),
                                  Text('1', style: TextStyle(fontFamily: 'Courier', fontWeight: FontWeight.bold)),
                                ],
                              ),
                              const SizedBox(height: 8),
                              const Align(
                                alignment: Alignment.centerLeft,
                                child: Text('USTED ESTA EN SU PAGO:\n#15 DE 40 PAGO', style: TextStyle(fontFamily: 'Courier', fontWeight: FontWeight.bold, height: 1.5)),
                              ),
                              const SizedBox(height: 8),
                              const Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text('IMPORTE:', style: TextStyle(fontFamily: 'Courier', fontWeight: FontWeight.bold)),
                                  Text('\$210.00', style: TextStyle(fontFamily: 'Courier', fontWeight: FontWeight.bold)),
                                ],
                              ),
                              const SizedBox(height: 8),
                              const Text('--------------------------------', style: TextStyle(fontFamily: 'Courier', fontWeight: FontWeight.bold)),
                              const Text('SALDO', style: TextStyle(fontFamily: 'Courier', fontWeight: FontWeight.bold, fontSize: 14)),
                              const Text('--------------------------------', style: TextStyle(fontFamily: 'Courier', fontWeight: FontWeight.bold)),
                              const SizedBox(height: 8),
                              const Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text('DEBE MORATORIAS:', style: TextStyle(fontFamily: 'Courier', fontWeight: FontWeight.bold)), Text('1', style: TextStyle(fontFamily: 'Courier', fontWeight: FontWeight.bold))]),
                              const SizedBox(height: 8),
                              const Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text('PAGOS ATRASADOS:', style: TextStyle(fontFamily: 'Courier', fontWeight: FontWeight.bold)), Text('0', style: TextStyle(fontFamily: 'Courier', fontWeight: FontWeight.bold))]),
                              const SizedBox(height: 8),
                              const Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text('PAGOS RESTANTES:', style: TextStyle(fontFamily: 'Courier', fontWeight: FontWeight.bold)), Text('25', style: TextStyle(fontFamily: 'Courier', fontWeight: FontWeight.bold))]),
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
                        _buildTextField('Encabezado del Ticket', _headerController, maxLines: 2),
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
                        _openBluetoothScreen();
                        return;
                      }
                      for (String line in _headerController.text.toUpperCase().split('\n')) {
                        bluetooth.printCustom(line, 2, 1);
                      }
                      bluetooth.printCustom('TEL ${_phoneController.text}', 1, 1);
                      bluetooth.printNewLine();
                      
                      bluetooth.printCustom('FECHA: 11/05/26   HORA: 08:57', 1, 0);
                      bluetooth.printCustom('CLIENTE: GINA JANET POO', 1, 0);
                      bluetooth.printCustom('PAGO DIARIO:\$210.0 PLAZO 40', 1, 0);
                      bluetooth.printCustom('VENCIMIENTO: 29/04/2026', 1, 0);
                      bluetooth.printCustom('LE ATENDIO: JUAN PEREZ', 1, 0);
                      
                      bluetooth.printCustom('--------------------------------', 1, 1);
                      bluetooth.printCustom('DETALLES DEL PAGO', 1, 1);
                      bluetooth.printCustom('--------------------------------', 1, 1);
                      
                      bluetooth.printLeftRight('PAGOS REALIZADOS:', '1', 1);
                      bluetooth.printCustom('USTED ESTA EN SU PAGO:', 1, 0);
                      bluetooth.printCustom('#15 DE 40 PAGO', 1, 0);
                      bluetooth.printLeftRight('IMPORTE:', '\$210.00', 1);
                      
                      bluetooth.printCustom('--------------------------------', 1, 1);
                      bluetooth.printCustom('SALDO', 1, 1);
                      bluetooth.printCustom('--------------------------------', 1, 1);
                      
                      bluetooth.printLeftRight('DEBE MORATORIAS:', '1', 1);
                      bluetooth.printLeftRight('PAGOS ATRASADOS:', '0', 1);
                      bluetooth.printLeftRight('PAGOS RESTANTES:', '25', 1);
                      bluetooth.printLeftRight('FALTA LIQUIDAR:', '\$5,250.00', 1);
                      
                      bluetooth.printNewLine();
                      bluetooth.printCustom(_footerController.text, 1, 1);
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

class BluetoothPrinterScreen extends StatefulWidget {
  final BlueThermalPrinter bluetooth;
  final List<BluetoothDevice> initialDevices;
  final BluetoothDevice? connectedDevice;
  final Function(BluetoothDevice) onDeviceConnected;
  final VoidCallback onDeviceDisconnected;

  const BluetoothPrinterScreen({
    super.key,
    required this.bluetooth,
    required this.initialDevices,
    this.connectedDevice,
    required this.onDeviceConnected,
    required this.onDeviceDisconnected,
  });

  @override
  State<BluetoothPrinterScreen> createState() => _BluetoothPrinterScreenState();
}

class _BluetoothPrinterScreenState extends State<BluetoothPrinterScreen> {
  List<BluetoothDevice> _devices = [];
  BluetoothDevice? _connectedDevice;
  bool _isConnecting = false;
  String? _connectingAddress;

  @override
  void initState() {
    super.initState();
    _devices = widget.initialDevices;
    _connectedDevice = widget.connectedDevice;
    if (_devices.isEmpty) {
      _refreshDevices();
    }
  }

  Future<void> _refreshDevices() async {
    List<BluetoothDevice> devices = [];
    try {
      devices = await widget.bluetooth.getBondedDevices();
    } on PlatformException {
      // ignore
    }
    if (mounted) {
      setState(() {
        _devices = devices;
      });
    }
  }

  Future<void> _connectToDevice(BluetoothDevice device) async {
    setState(() {
      _isConnecting = true;
      _connectingAddress = device.address;
    });

    try {
      // 1. Siempre verificamos el estado real del plugin en Android, no solo nuestra variable local
      bool? isCurrentlyConnected = await widget.bluetooth.isConnected;
      
      // 2. Si el plugin dice que ya hay una conexión activa (incluso si fue en una sesión anterior), la desconectamos por la fuerza.
      if (isCurrentlyConnected == true) {
        await widget.bluetooth.disconnect();
        // Le damos un respiro al hardware de Bluetooth para cerrar el socket
        await Future.delayed(const Duration(milliseconds: 300));
      }
      
      // 3. Ahora sí, intentamos la conexión limpia
      await widget.bluetooth.connect(device);
      bool? isConnected = await widget.bluetooth.isConnected;
      
      if (isConnected == true) {
        setState(() {
          _connectedDevice = device;
        });
        widget.onDeviceConnected(device);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Conectado a ${device.name}', style: const TextStyle(color: Colors.white)), backgroundColor: Colors.green));
          Navigator.pop(context); // Regresar al ticket screen
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error de conexión: $e', style: const TextStyle(color: Colors.white)), backgroundColor: Colors.red));
      }
    } finally {
      if (mounted) {
        setState(() {
          _isConnecting = false;
          _connectingAddress = null;
        });
      }
    }
  }

  Future<void> _disconnect() async {
    await widget.bluetooth.disconnect();
    setState(() {
      _connectedDevice = null;
    });
    widget.onDeviceDisconnected();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F6FB), // Light bluish gray background matching the image
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 0,
        centerTitle: true,
        title: const Text('Impresora Bluetooth', style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _refreshDevices,
          ),
        ],
      ),
      body: _devices.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Text(
                  'No hay dispositivos bluetooth vinculados.\nPor favor vincule la impresora desde la configuración de su teléfono primero.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 16),
                ),
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _devices.length,
              itemBuilder: (context, index) {
                final device = _devices[index];
                final isThisConnected = _connectedDevice?.address == device.address;
                final isConnectingToThis = _isConnecting && _connectingAddress == device.address;

                return Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.02),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        // Icon container
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFFE8F0FE), // Light blue background for icon
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(
                            Icons.print_outlined,
                            color: Color(0xFF09305A),
                            size: 24,
                          ),
                        ),
                        const SizedBox(width: 16),
                        
                        // Device info
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                device.name ?? 'Desconocido',
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.black87),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                device.address ?? '',
                                style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                              ),
                            ],
                          ),
                        ),
                        
                        // Action button
                        ElevatedButton(
                          onPressed: isConnectingToThis 
                              ? null 
                              : (isThisConnected ? _disconnect : () => _connectToDevice(device)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: isThisConnected ? Colors.red.shade50 : const Color(0xFF0B1426), // Dark navy for Connect
                            foregroundColor: isThisConnected ? Colors.red.shade700 : Colors.white,
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(24), // Pill shape
                            ),
                          ),
                          child: isConnectingToThis
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                                )
                              : Text(
                                  isThisConnected ? 'Desconectar' : 'Conectar',
                                  style: const TextStyle(fontWeight: FontWeight.bold),
                                ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }
}


