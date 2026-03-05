import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class ThemeProvider with ChangeNotifier {
  bool _isDarkMode = false;
  bool _isLoaded = false;

  bool get isDarkMode => _isDarkMode;
  bool get isLoaded => _isLoaded;

  ThemeMode get themeMode =>
      _isLoaded ? (_isDarkMode ? ThemeMode.dark : ThemeMode.light) : ThemeMode.light;

  ThemeProvider() {
    _waitForUserAndLoadTheme();
  }

  void _waitForUserAndLoadTheme() {
    // Listen to auth state changes and wait for a user to be available
    FirebaseAuth.instance.authStateChanges().listen((user) async {
      if (user != null) {
        final doc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
        _isDarkMode = doc.data()?['isDarkMode'] ?? false;
      }
      _isLoaded = true;
      notifyListeners();
    });
  }

  void toggleTheme(bool isOn) async {
    _isDarkMode = isOn;
    notifyListeners();

    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .update({'isDarkMode': isOn});
    }
  }
}