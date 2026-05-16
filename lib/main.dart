// ignore_for_file: avoid_print
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'screens/login_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  print('--- INICIANDO SUPABASE ---');
  try {
    await Supabase.initialize(
      url: 'https://qgfynikzzasiqefzhmuh.supabase.co',
      anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InFnZnluaWt6emFzaXFlZnpobXVoIiwicm9sZSI6ImFub24iLCJpYXQiOjE3Nzg0NTUwNDAsImV4cCI6MjA5NDAzMTA0MH0.EVhvORE2_7ZmWcIBcbuxavYJshsezZw_hbolfSqBci8',
    );
    print('--- SUPABASE INICIALIZADO CORRECTAMENTE ---');
  } catch (e) {
    print('--- ERROR AL INICIALIZAR SUPABASE: $e ---');
  }

  runApp(const FinancieraApp());
}

class FinancieraApp extends StatelessWidget {
  const FinancieraApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Financiera Regional',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF09305A)),
        useMaterial3: true,
      ),
      home: const LoginScreen(),
    );
  }
}
