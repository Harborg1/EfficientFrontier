import 'package:backtesting/screens/login_screen.dart';
import 'package:backtesting/screens/saved_portfolios.dart';
import 'package:flutter/material.dart';
import 'package:backtesting/screens/frontier_screen.dart'; 
import 'package:backtesting/screens/settings_screen.dart';
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
    // Grab the current theme so we can use its colors dynamically
    final theme = Theme.of(context);

    return Scaffold(
      // REMOVED: backgroundColor: Colors.white
      // Now it will automatically use your ThemeData.scaffoldBackgroundColor
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const SettingsScreen()),
              );
            },
            icon: Icon(Icons.settings_outlined, color: theme.colorScheme.onSurfaceVariant),
            tooltip: 'Settings',
          ),
          IconButton(
            onPressed: () => _handleLogout(context),
            icon: Icon(Icons.logout_rounded, color: theme.colorScheme.onSurfaceVariant),
            tooltip: 'Logout',
          ),
        ],
      ),
      body: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 400),
          padding: const EdgeInsets.symmetric(horizontal: 32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // STOCK THEMED ICON
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.green.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.query_stats_rounded,
                  size: 80,
                  color: Colors.green, // Kept green since it's an isolated brand element
                ),
              ),
              const SizedBox(height: 32),
              Text(
                "Portfolio Optimizer",
                style: TextStyle(
                  fontSize: 28, 
                  fontWeight: FontWeight.w900,
                  // CHANGED: Use the primary color from your theme (Dark Navy in light, Lighter Blue in dark)
                  color: theme.colorScheme.primary, 
                  letterSpacing: -0.5,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Text(
                "Your portfolio optimizer is ready. Analyze risk, maximize returns, and backtest your next move.",
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 15, 
                  // CHANGED: Use a theme-aware muted color instead of hardcoded blueGrey
                  color: theme.colorScheme.onSurfaceVariant, 
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 48),
              
              // PRIMARY ACTION: GET STARTED
              SizedBox(
                width: double.infinity,
                height: 56,
                child: FilledButton.icon(
                  // REMOVED: Custom styleFrom with hardcoded background color. 
                  // It will now automatically use the filledButtonTheme you defined in your ThemeData!
                  onPressed: () {
                    Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(builder: (context) => const FrontierScreen()),
                    );
                  },
                  icon: const Icon(Icons.analytics_outlined, size: 20),
                  label: const Text(
                    "Launch Optimizer", 
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // SECONDARY ACTION: SAVED PORTFOLIOS
              SizedBox(
                width: double.infinity,
                height: 56,
                child: OutlinedButton.icon(
                  // REMOVED: Custom BorderSide and foregroundColor.
                  style: OutlinedButton.styleFrom(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: () {
                    Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(builder: (context) => const SavedPortfoliosScreen()),
                    );
                  },
                  icon: const Icon(Icons.folder_special_outlined, size: 20),
                  label: const Text(
                    "Portfolio History",
                    style: TextStyle(fontSize: 16),
                  ),
                ),
              ),
              const SizedBox(height: 40),
              
              // DECORATIVE BOTTOM TEXT
              const Text(
                "MARKET DATA SYNCED",
                style: TextStyle(
                  fontSize: 10, 
                  fontWeight: FontWeight.bold, 
                  color: Colors.green, // Kept green to match the logo icon
                  letterSpacing: 2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}