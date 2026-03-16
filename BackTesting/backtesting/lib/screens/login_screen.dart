import 'package:backtesting/screens/register_screen.dart';
import 'package:flutter/material.dart';
import 'package:backtesting/screens/welcome_screen.dart';
import 'package:firebase_auth/firebase_auth.dart';

void main() {
  runApp(const LoginApp());
}

// Grundlæggende wrapper for appen
class LoginApp extends StatelessWidget {
  const LoginApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Simpel Login Demo',
      theme: ThemeData(
        // Bruger Material 3 tema for et moderne udseende
        useMaterial3: true,
        colorSchemeSeed: Colors.blue,
      ),
      home: const LoginScreen(),
    );
  }
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  // 1. Opret controllere til at fange brugerinput
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  // 2. Opret en global nøgle, der unikt identificerer Form-widgetten
  // og gør det muligt at validere formularen.
  final _formKey = GlobalKey<FormState>();

  // Tilstandsvariabel til at håndtere visning/skjul af adgangskode
  bool _erAdgangskodeSynlig = false;

  @override
  void dispose() {
    // Ryd op i controllere, når widgetten fjernes.
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  // Funktion der kaldes, når der trykkes på login-knappen
  Future<void> _haandterLogin() async {
    // Valider formularens lokale tilstand først
    if (_formKey.currentState!.validate()) {
      
      // Vis en indlæsningsindikator (valgfrit men anbefales)
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(child: CircularProgressIndicator()),
      );

      try {
        // 2. Kald Firebase for at verificere brugeren
        await FirebaseAuth.instance.signInWithEmailAndPassword(
          email: _emailController.text.trim(),
          password: _passwordController.text.trim(),
        );

        // 3. Luk indlæsningsindikatoren
        if (mounted) Navigator.of(context).pop();

        // 4. Naviger til Velkomstskærmen
        if (mounted) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (context) => const WelcomeScreen()),
          );
        }
      } on FirebaseAuthException catch (e) {
        // 5. Håndter fejl (Luk indlæser først)
        if (mounted) Navigator.of(context).pop();
        
        String besked = 'Der opstod en fejl. Prøv venligst igen.';
        if (e.code == 'user-not-found') {
          besked = 'Ingen bruger fundet med den e-mail.';
        } else if (e.code == 'wrong-password') {
          besked = 'Forkert adgangskode.';
        } else if (e.code == 'invalid-email') {
          besked = 'E-mail adressen er forkert formateret.';
        }

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(besked), backgroundColor: Colors.redAccent),
        );
      } catch (e) {
        if (mounted) Navigator.of(context).pop();
        print(e); // Til fejlfinding
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // Simpel App Bar
      appBar: AppBar(
        title: const Text("Velkommen tilbage"),
        centerTitle: true,
      ),
      // Centrer indholdet lodret på skærmen
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // --- Logo eller Overskriftsikon ---
                const Icon(
                  Icons.lock_outline_rounded,
                  size: 100,
                  color: Colors.blueAccent,
                ),
                const SizedBox(height: 40),

                // --- E-mail inputfelt ---
                TextFormField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: 'E-mail adresse',
                    prefixIcon: Icon(Icons.email_outlined),
                    border: OutlineInputBorder(),
                  ),
                  // Validatoren modtager den tekst, brugeren har indtastet.
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Indtast venligst din e-mail';
                    }
                    // Simpelt tjek for '@' symbolet
                    if (!value.contains('@')) {
                      return 'Indtast venligst en gyldig e-mail';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 20),

                // --- Adgangskode inputfelt ---
                TextFormField(
                  controller: _passwordController,
                  obscureText: !_erAdgangskodeSynlig, // Skifter synlighed
                  textInputAction: TextInputAction.done,
                  decoration: InputDecoration(
                    labelText: 'Adgangskode',
                    prefixIcon: const Icon(Icons.lock_outlined),
                    border: const OutlineInputBorder(),
                    // Lille øje-ikon knap til at vise/skjule adgangskode
                    suffixIcon: IconButton(
                      icon: Icon(
                        _erAdgangskodeSynlig
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                      ),
                      onPressed: () {
                        // Opdater tilstand for at skifte synligheds-variabel
                        setState(() {
                          _erAdgangskodeSynlig = !_erAdgangskodeSynlig;
                        });
                      },
                    ),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Indtast venligst din adgangskode';
                    }
                    if (value.length < 6) {
                      return 'Adgangskoden skal være på mindst 6 tegn';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 30),

                // --- Login-knap ---
                FilledButton(
                  onPressed: _haandterLogin,
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    textStyle: const TextStyle(fontSize: 18),
                  ),
                  child: const Text('Log ind'),
                ),
                
                const SizedBox(height: 16),
                // Simpelt "Glemt adgangskode" eller "Opret bruger" link
                TextButton(
                  onPressed: () {
                    Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(builder: (context) => const RegisterScreen()),
                    );
                  }, 
                  child: const Text("Har du ikke en konto? Opret dig her")
                )
              ],
            ),
          ),
        ),
      ),
    );
  }
}