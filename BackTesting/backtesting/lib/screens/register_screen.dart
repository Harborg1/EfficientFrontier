import 'package:flutter/material.dart';
import 'package:backtesting/screens/login_screen.dart';
import 'package:backtesting/screens/welcome_screen.dart'; // Importér den nye skærm
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  
  final _navnController = TextEditingController();
  final _emailController = TextEditingController();
  final _adgangskodeController = TextEditingController();
  final _bekraeftAdgangskodeController = TextEditingController();

  bool _erAdgangskodeSynlig = false;

  @override
  void dispose() {
    _navnController.dispose();
    _emailController.dispose();
    _adgangskodeController.dispose();
    _bekraeftAdgangskodeController.dispose();
    super.dispose();
  }

  Future<void> _haandterOpretBruger() async {
    if (_formKey.currentState!.validate()) {
      try {
        // 1. Opret brugeren i Firebase Authentication
        UserCredential brugerOplysninger = await FirebaseAuth.instance
            .createUserWithEmailAndPassword(
          email: _emailController.text.trim(),
          password: _adgangskodeController.text.trim(),
        );

        // 2. Gem ekstra data (brugernavn) i Firestore
        // Vi bruger det unikke UID fra Auth til at navngive dokumentet
        await FirebaseFirestore.instance
            .collection('users')
            .doc(brugerOplysninger.user!.uid)
            .set({
          'username': _navnController.text.trim(),
          'email': _emailController.text.trim(),
          'createdAt': DateTime.now(),
        });

        // 3. Navigér til Velkomstskærmen
        if (mounted) {
          Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute(builder: (context) => const WelcomeScreen()),
            (route) => false,
          );
        }
      } on FirebaseAuthException catch (e) {
        // Håndtér fejl (f.eks. hvis e-mailen allerede er i brug)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message ?? 'Der opstod en fejl')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Opret konto"),
        centerTitle: true,
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Icon(
                  Icons.person_add_outlined,
                  size: 100,
                  color: Colors.blueAccent,
                ),
                const SizedBox(height: 30),

                // --- Brugernavn felt ---
                TextFormField(
                  controller: _navnController,
                  decoration: const InputDecoration(
                    labelText: 'Brugernavn',
                    prefixIcon: Icon(Icons.person_outline),
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) => (value == null || value.isEmpty) ? 'Indtast et brugernavn' : null,
                ),
                const SizedBox(height: 16),

                // --- E-mail felt ---
                TextFormField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    labelText: 'E-mail adresse',
                    prefixIcon: Icon(Icons.email_outlined),
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) => (value != null && value.contains('@')) ? null : 'Indtast en gyldig e-mail',
                ),
                const SizedBox(height: 16),

                // --- Adgangskode felt ---
                TextFormField(
                  controller: _adgangskodeController,
                  obscureText: !_erAdgangskodeSynlig,
                  decoration: InputDecoration(
                    labelText: 'Adgangskode',
                    prefixIcon: const Icon(Icons.lock_outline),
                    suffixIcon: IconButton(
                      icon: Icon(_erAdgangskodeSynlig ? Icons.visibility : Icons.visibility_off),
                      onPressed: () => setState(() => _erAdgangskodeSynlig = !_erAdgangskodeSynlig),
                    ),
                    border: const OutlineInputBorder(),
                  ),
                  validator: (value) => (value != null && value.length >= 6) ? null : 'Mindst 6 tegn påkrævet',
                ),
                const SizedBox(height: 16),

                // --- Bekræft adgangskode felt ---
                TextFormField(
                  controller: _bekraeftAdgangskodeController,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Bekræft adgangskode',
                    prefixIcon: Icon(Icons.lock_reset),
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) {
                    if (value != _adgangskodeController.text) return 'Adgangskoderne er ikke ens';
                    return null;
                  },
                ),
                const SizedBox(height: 24),

                // --- Opret konto knap ---
                FilledButton(
                  onPressed: _haandterOpretBruger,
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: const Text('Opret konto'),
                ),
                
                // --- Skift til login ---
                TextButton(
                  onPressed: () {
                    // Navigér til LoginScreen widgetten
                    Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(builder: (context) => const LoginScreen()),
                    );
                  }, 
                  child: const Text("Har du allerede en konto? Log ind"),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}