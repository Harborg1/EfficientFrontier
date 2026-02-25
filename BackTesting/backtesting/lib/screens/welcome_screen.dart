import 'package:flutter/material.dart';
// 1. Add this import so the file knows what FrontierScreen is
import 'package:backtesting/screens/frontier_screen.dart'; 

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
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
                "Your account has been successfully created. You can now start testing your strategies.",
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16, color: Colors.grey),
              ),
              const SizedBox(height: 40),
              FilledButton.icon(
                onPressed: () {
                  // 2. Replace the SnackBar with actual navigation
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const FrontierScreen(),
                    ),
                  );
                },
                icon: const Icon(Icons.rocket_launch),
                label: const Text("Get Started"),
              ),
            ],
          ),
        ),
      ),
    );
  }
}