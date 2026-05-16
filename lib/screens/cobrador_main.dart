import 'package:flutter/material.dart';
import 'cobrador_home.dart';
import 'cobrador_buscar_screen.dart';
import 'cobrador_config_screen.dart';

class CobradorMainScreen extends StatefulWidget {
  const CobradorMainScreen({super.key});

  @override
  State<CobradorMainScreen> createState() => _CobradorMainScreenState();
}

class _CobradorMainScreenState extends State<CobradorMainScreen> {
  int _currentIndex = 0;

  final List<Widget> _screens = [
    const CobradorHomeScreen(),
    const CobradorBuscarScreen(),
    const CobradorConfigScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: _screens,
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        selectedItemColor: const Color(0xFF09305A),
        unselectedItemColor: Colors.grey,
        showUnselectedLabels: true,
        backgroundColor: Colors.white,
        elevation: 10,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home_rounded), label: 'Inicio'),
          BottomNavigationBarItem(icon: Icon(Icons.search_rounded), label: 'Buscar'),
          BottomNavigationBarItem(icon: Icon(Icons.settings_rounded), label: 'Config'),
        ],
        onTap: (index) {
          setState(() {
            _currentIndex = index;
          });
        },
      ),
    );
  }
}
