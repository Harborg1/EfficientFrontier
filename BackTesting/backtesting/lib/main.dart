import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:backtesting/firebase_options.dart'; 
import 'package:backtesting/screens/register_screen.dart'; 
import 'package:backtesting/screens/frontier_screen.dart'; // Import is correct now

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Backtesting App',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      // To test the chart immediately, use FrontierScreen()
      // To test the login flow, use RegisterScreen()
      home: const RegisterScreen(), 
    );
  }
}