import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'config_editor_percent.dart';
import 'config_descanso_screen.dart';
import 'config_ticket_screen.dart';

class ConfiguracionTab extends StatefulWidget {
  const ConfiguracionTab({super.key});

  @override
  State<ConfiguracionTab> createState() => _ConfiguracionTabState();
}

class _ConfiguracionTabState extends State<ConfiguracionTab> {
  Future<void> _cerrarSesion() async {
    await Supabase.instance.client.auth.signOut();
    if (mounted) {
      Navigator.pushNamedAndRemoveUntil(context, '/', (route) => false);
    }
  }

  // Navigation helper
  void _navigateTo(Widget screen) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => screen),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Header
        Container(
          width: double.infinity,
          padding: EdgeInsets.only(
            top: MediaQuery.of(context).padding.top + 20,
            left: 24,
            right: 24,
            bottom: 20,
          ),
          color: const Color(0xFF09305A),
          child: const Text(
            'Configuración',
            style: TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        
        // Listado de configuraciones
        Expanded(
          child: Container(
            color: const Color(0xFFF3F4F6),
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    children: [
                      _buildConfigItem(
                        icon: Icons.percent,
                        title: 'Intereses',
                        subtitle: 'Porcentaje base por préstamo',
                        onTap: () => _navigateTo(const ConfigEditorPercentScreen(
                          title: 'Intereses',
                          hint: 'Porcentaje base por préstamo',
                          dbColumn: 'tasa_interes_base',
                          simulationLabel: 'Ganancia (Dueño)',
                        )),
                      ),
                      _buildDivider(),
                      _buildConfigItem(
                        icon: Icons.schedule,
                        title: 'Moratorios',
                        subtitle: 'Costo por día de retraso',
                        onTap: () => _navigateTo(const ConfigEditorPercentScreen(
                          title: 'Moratorios',
                          hint: 'Costo por día de retraso',
                          dbColumn: 'porcentaje_mora_diaria',
                          simulationLabel: 'Penalización',
                        )),
                      ),
                      _buildDivider(),
                      _buildConfigItem(
                        icon: Icons.receipt_long,
                        title: 'Diseño de Ticket',
                        subtitle: 'Encabezado y pie de página',
                        onTap: () => _navigateTo(const ConfigTicketScreen()),
                      ),
                      _buildDivider(),
                      _buildConfigItem(
                        icon: Icons.gpp_maybe_outlined,
                        title: 'Reglas de Incumplimiento',
                        subtitle: 'Bloqueos automáticos (30 días)',
                        onTap: () => _navigateTo(const ConfigEditorPercentScreen(
                          title: 'Reglas de Incumplimiento',
                          hint: 'Porcentaje penalización grave (30 días)',
                          dbColumn: 'penalizacion_incumplimiento_30d',
                          simulationLabel: 'Penalización Grave',
                        )),
                      ),
                      _buildDivider(),
                      _buildConfigItem(
                        icon: Icons.calendar_month,
                        title: 'Porcentaje de Cuota Diaria',
                        subtitle: 'Ej. 5.0 para 5% del capital',
                        onTap: () => _navigateTo(const ConfigEditorPercentScreen(
                          title: 'Porcentaje de Cuota Diaria',
                          hint: 'Ej. 5.0 para 5% del capital',
                          dbColumn: 'porcentaje_cuota_diaria',
                          simulationLabel: 'Pago Diario',
                        )),
                      ),
                      _buildDivider(),
                      _buildConfigItem(
                        icon: Icons.people_outline,
                        title: 'Comisión de cobradores',
                        subtitle: 'Ganancia por recolección',
                         onTap: () => _navigateTo(const ConfigEditorPercentScreen(
                          title: 'Comisión de cobradores',
                          hint: 'Porcentaje de comisión para el cobrador',
                          dbColumn: 'comision_porcentaje',
                          simulationLabel: 'Ganancia Cobrador',
                        )),
                      ),
                      _buildDivider(),
                      _buildConfigItem(
                        icon: Icons.wb_sunny_outlined,
                        title: 'Descanso',
                        subtitle: 'Fechas sin cobro de moratorias',
                        onTap: () => _navigateTo(const ConfigDescansoScreen()),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                // Botón de Cerrar Sesión
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _cerrarSesion,
                    icon: const Icon(Icons.logout_rounded, color: Colors.white),
                    label: const Text(
                      'Cerrar Sesión',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFDC2626), // Rojo
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 0,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildConfigItem({required IconData icon, required String title, required String subtitle, required VoidCallback onTap}) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      leading: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFFF3F4F6),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, color: const Color(0xFF09305A)),
      ),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF09305A))),
      subtitle: Text(subtitle, style: const TextStyle(color: Colors.grey, fontSize: 14)),
      trailing: const Icon(Icons.chevron_right, color: Colors.grey),
      onTap: onTap,
    );
  }

  Widget _buildDivider() {
    return const Divider(height: 1, thickness: 1, color: Color(0xFFF3F4F6));
  }
}
