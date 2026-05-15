import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:backtesting/screens/welcome_screen.dart'; // Import WelcomeScreen for navigation

class SavedPortfoliosScreen extends StatelessWidget {
  const SavedPortfoliosScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    return Scaffold(
      appBar: AppBar(
        title: const Text("My Saved Portfolios"),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (context) => const WelcomeScreen()),
            );
          },
        ),
      ),
      
      body: user == null
          ? const Center(child: Text("Log in to view saved portfolios."))
          : StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('users')
                  .doc(user.uid)
                  .collection('saved_portfolios')
                  .orderBy('timestamp', descending: true)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.hasError) return const Center(child: Text("Error loading data"));
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                final docs = snapshot.data!.docs;
                if (docs.isEmpty) {
                  return const Center(child: Text("No saved portfolios found."));
                }

                return ListView.builder(
                  itemCount: docs.length,
                  padding: const EdgeInsets.all(8),
                  itemBuilder: (context, index) {
                    final data = docs[index].data() as Map<String, dynamic>;
                    final String typeVisning = data.containsKey('sortino')
                        ? 'Max Sortino'
                        : data['type'] ?? 'Portfolio';
                    final bool isMaxSharpe = typeVisning == 'Max Sharpe';
                    final bool isMaxSortino = typeVisning == 'Max Sortino';
                    return Card(
                      margin: const EdgeInsets.symmetric(vertical: 8),
                      child: ListTile(
                        leading: Icon(
                          isMaxSharpe
                              ? Icons.trending_up
                              : isMaxSortino
                                  ? Icons.trending_up_outlined
                                  : Icons.shield_outlined,
                          color: isMaxSharpe
                              ? Colors.red
                              : isMaxSortino
                                  ? Colors.purple
                                  : Colors.blue,
                        ),
                        title: Text("$typeVisning: ${data['tickers'].join(', ')}"),
                        subtitle: Text("Annual Return: ${(data['return'] * 100).toStringAsFixed(2)}%"),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () => _confirmDelete(context, docs[index].reference),
                        ),
                        onTap: () => _showWeightsDialog(context, data),
                      ),
                    );
                  },
                );
              },
            ),
    );
  }

  void _confirmDelete(BuildContext context, DocumentReference ref) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Delete Portfolio?"),
        content: const Text("This action cannot be undone."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
          TextButton(
            onPressed: () {
              ref.delete();
              Navigator.pop(context);
            },
            child: const Text("Delete", style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  void _showWeightsDialog(BuildContext context, Map<String, dynamic> data) {
    final String typeVisning = data.containsKey('sortino')
        ? 'Max Sortino'
        : data['type'] ?? 'Portfolio';

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text("Distribution: $typeVisning"),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: (data['weights'] as Map<String, dynamic>).entries.map((e) => 
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(e.key, style: const TextStyle(fontWeight: FontWeight.bold)),
                    Text("${(e.value * 100).toStringAsFixed(1)}%"),
                  ],
                ),
              )
            ).toList(),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Close")),
        ],
      ),
    );
  }
}
