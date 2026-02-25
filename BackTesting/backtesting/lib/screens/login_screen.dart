import 'package:backtesting/screens/register_screen.dart';
import 'package:flutter/material.dart';
import 'package:backtesting/screens/welcome_screen.dart';

void main() {
  runApp(const LoginApp());
}

// Basic wrapper for the app
class LoginApp extends StatelessWidget {
  const LoginApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Simple Login Demo',
      theme: ThemeData(
        // Using Material 3 theme for modern look
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
  // 1. Create controllers to capture user input
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  // 2. Create a global key that uniquely identifies the Form widget
  // and allows validation of the form.
  final _formKey = GlobalKey<FormState>();

  // State variable to handle password visibility toggling
  bool _isPasswordVisible = false;

  @override
  void dispose() {
    // Clean up controllers when the widget is disposed.
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  // Function called when the login button is pressed
  // Function called when the login button is pressed
  void _handleLogin() {
    // Validate returns true if the form is valid, or false otherwise.
    if (_formKey.currentState!.validate()) {

      // --- ADD THIS NAVIGATION BLOCK ---
      // We use pushReplacement so the user can't hit the "Back" button to go back to the login screen
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => const WelcomeScreen(),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // Simple App Bar
      appBar: AppBar(
        title: const Text("Welcome Back"),
        centerTitle: true,
      ),
      // Center the content vertically on the screen
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // --- Logo or Header Icon ---
                const Icon(
                  Icons.lock_outline_rounded,
                  size: 100,
                  color: Colors.blueAccent,
                ),
                const SizedBox(height: 40),

                // --- Email Input Field ---
                TextFormField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: 'Email Address',
                    prefixIcon: Icon(Icons.email_outlined),
                    border: OutlineInputBorder(),
                  ),
                  // The validator receives the text that the user has entered.
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Please enter your email';
                    }
                    // Simple check for '@' symbol
                    if (!value.contains('@')) {
                       return 'Please enter a valid email';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 20),

                // --- Password Input Field ---
                TextFormField(
                  controller: _passwordController,
                  obscureText: !_isPasswordVisible, // Toggles visibility
                  textInputAction: TextInputAction.done,
                  decoration: InputDecoration(
                    labelText: 'Password',
                    prefixIcon: const Icon(Icons.lock_outlined),
                    border: const OutlineInputBorder(),
                    // The little eye icon button to show/hide password
                    suffixIcon: IconButton(
                      icon: Icon(
                        _isPasswordVisible
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                      ),
                      onPressed: () {
                        // Update state to toggle visibility variable
                        setState(() {
                          _isPasswordVisible = !_isPasswordVisible;
                        });
                      },
                    ),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Please enter your password';
                    }
                    if (value.length < 6) {
                      return 'Password must be at least 6 characters';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 30),

                // --- Login Button ---
                FilledButton(
                  onPressed: _handleLogin,
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    textStyle: const TextStyle(fontSize: 18),
                  ),
                  child: const Text('Login'),
                ),
                
                const SizedBox(height: 16),
                // Simple "Forgot Password" or "Sign Up" link
                TextButton(
                  onPressed: () {
                     Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(builder: (context) => const RegisterScreen()),
                    );
                  }, 
                  child: const Text("Don't have an account? Sign up")
                )
              ],
            ),
          ),
        ),
      ),
    );
  }
}