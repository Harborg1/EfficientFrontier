import 'package:backtesting/theme/theme.dart';
import 'package:backtesting/theme/theme_provider.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:backtesting/firebase_options.dart'; 
import 'package:backtesting/screens/register_screen.dart'; 
import 'package:provider/provider.dart';
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // WRAP THE APP HERE
  runApp(
    ChangeNotifierProvider(
      create: (context) => ThemeProvider(),
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    // Now this 'context' can see the ThemeProvider because it's wrapped above it
    final themeProvider = Provider.of<ThemeProvider>(context);

    return MaterialApp(
      title: 'Backtesting App',
      debugShowCheckedModeBanner: false,
      theme: lightMode, // Ensure these are imported from your theme.dart
      darkTheme: darkMode,
      themeMode: themeProvider.themeMode,
      home: const RegisterScreen(), 
    );
  }
}