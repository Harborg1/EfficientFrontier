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
        title: const Text("Mine gemte porteføljer"),
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
          ? const Center(child: Text("Log venligst ind for at se gemte porteføljer."))
          : StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('users')
                  .doc(user.uid)
                  .collection('saved_portfolios')
                  .orderBy('timestamp', descending: true)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.hasError) return const Center(child: Text("Fejl ved indlæsning af data"));
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                final docs = snapshot.data!.docs;
                if (docs.isEmpty) {
                  return const Center(child: Text("Ingen gemte porteføljer fundet."));
                }

                return ListView.builder(
                  itemCount: docs.length,
                  padding: const EdgeInsets.all(8),
                  itemBuilder: (context, index) {
                    final data = docs[index].data() as Map<String, dynamic>;
                    final bool isMaxSharpe = data['type'] == 'Max Sharpe';
                    // Oversættelse af type til visning
                    final String typeVisning = isMaxSharpe ? 'Maks Sharpe' : 'Min Risiko';

                    return Card(
                      margin: const EdgeInsets.symmetric(vertical: 8),
                      child: ListTile(
                        leading: Icon(
                          isMaxSharpe ? Icons.trending_up : Icons.shield_outlined,
                          color: isMaxSharpe ? Colors.red : Colors.blue,
                        ),
                        title: Text("$typeVisning: ${data['tickers'].join(', ')}"),
                        subtitle: Text("Årligt afkast: ${(data['return'] * 100).toStringAsFixed(2)}%"),
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
        title: const Text("Slet portefølje?"),
        content: const Text("Denne handling kan ikke fortrydes."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Annuller")),
          TextButton(
            onPressed: () {
              ref.delete();
              Navigator.pop(context);
            },
            child: const Text("Slet", style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  void _showWeightsDialog(BuildContext context, Map<String, dynamic> data) {
    final String typeVisning = data['type'] == 'Max Sharpe' ? 'Maks Sharpe' : 'Min Risiko';

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text("Fordeling: $typeVisning"),
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
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Luk")),
        ],
      ),
    );
  }
}