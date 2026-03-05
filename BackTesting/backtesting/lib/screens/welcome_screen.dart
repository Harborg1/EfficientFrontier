import 'package:backtesting/screens/login_screen.dart';
import 'package:backtesting/screens/saved_portfolios.dart';
import 'package:flutter/material.dart';
import 'package:backtesting/screens/frontier_screen.dart'; 
import 'package:backtesting/screens/settings_screen.dart'; // 1. Import your Settings Screen
import 'package:firebase_auth/firebase_auth.dart';

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  Future<void> _handleLogout(BuildContext context) async {
    await FirebaseAuth.instance.signOut();
    
    if (context.mounted) {
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (context) => const LoginScreen()),
        (route) => false,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        // 2. We use 'actions' to place buttons at the end of the AppBar
        actions: [
          // Settings Button
          IconButton(
            onPressed: () {
              // 3. Simple push navigation (keeping WelcomeScreen in the stack)
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const SettingsScreen()),
              );
            },
            icon: const Icon(Icons.settings),
            tooltip: 'Settings',
          ),
          
          // Logout Button
          IconButton(
            onPressed: () => _handleLogout(context),
            icon: const Icon(Icons.logout),
            tooltip: 'Logout',
          ),
        ],
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.celebration_rounded,
                size: 100,
                color: Colors.orangeAccent,
              ),
              const SizedBox(height: 24),
              const Text(
                "Welcome to Backtesting!",
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              const Text(
                "Your account is active. You can now start testing your strategies.",
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16, color: Colors.grey),
              ),
              const SizedBox(height: 40),
              
              // Get Started Button
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () {
                    Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(builder: (context) => const FrontierScreen()),
                    );
                  },
                  icon: const Icon(Icons.rocket_launch),
                  label: const Text("Get Started"),
                ),
              ),
              const SizedBox(height: 12),

              // Saved Portfolios Button
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () {
                    Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(builder: (context) => const SavedPortfoliosScreen()),
                    );
                  },
                  icon: const Icon(Icons.save),
                  label: const Text("Saved Portfolios"),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}