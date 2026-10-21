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
                if (snapshot.hasError)
                  return const Center(child: Text("Error loading data"));
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                final docs = snapshot.data!.docs;
                if (docs.isEmpty) {
                  return const Center(
                    child: Text("No saved portfolios found."),
                  );
                }

                return ListView.builder(
                  itemCount: docs.length,
                  padding: const EdgeInsets.all(8),
                  itemBuilder: (context, index) {
                    final data = docs[index].data() as Map<String, dynamic>;
                    final String typeVisning = _portfolioType(data);
                    final bool isMaxSharpe = typeVisning.contains('Sharpe');
                    final bool isMaxSortino = typeVisning.contains('Sortino');
                    final subtitle = _portfolioSubtitle(data);
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
                        title: Text(
                          "$typeVisning: ${data['tickers'].join(', ')}",
                        ),
                        subtitle: Text(subtitle),
                        isThreeLine: subtitle.contains('\n'),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () =>
                              _confirmDelete(context, docs[index].reference),
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

  String _portfolioType(Map<String, dynamic> data) {
    return data['type']?.toString() ??
        (data.containsKey('sortino') ? 'Max Sortino' : 'Portfolio');
  }

  String _portfolioSubtitle(Map<String, dynamic> data) {
    String percentage(String label, num value) {
      return "$label: ${(value.toDouble() * 100).toStringAsFixed(2)}%";
    }

    final annualReturn = data['return'];
    final returnText = annualReturn is num
        ? percentage("Annual Return", annualReturn)
        : "Annual Return: N/A";

    final primaryMetrics = <String>[returnText];
    final cagr = data['cagr'];
    if (cagr is num) {
      primaryMetrics.add(percentage("CAGR", cagr));
    }

    final secondaryDetails = <String>[];
    final alpha = data['alpha'];
    if (alpha is num) {
      secondaryDetails.add(percentage("Alpha", alpha));
    }

    final beta = data['beta'];
    if (beta is num) {
      secondaryDetails.add("Beta: ${beta.toDouble().toStringAsFixed(2)}");
    }

    final interval = data['rebalance_interval_months'];
    if (interval is num && interval > 0) {
      final label =
          data['rebalance_label']?.toString() ?? "Every $interval months";
      secondaryDetails.add("Rebalance: $label");
    }

    if (secondaryDetails.isEmpty) {
      return primaryMetrics.join(" | ");
    }

    return "${primaryMetrics.join(" | ")}\n${secondaryDetails.join(" | ")}";
  }

  List<MapEntry<String, String>> _portfolioMetrics(Map<String, dynamic> data) {
    String percentage(num value) {
      return "${(value.toDouble() * 100).toStringAsFixed(2)}%";
    }

    String ratio(num value) => value.toDouble().toStringAsFixed(2);

    final metrics = <MapEntry<String, String>>[];
    final metricDefinitions = <({String key, String label, bool isPercentage})>[
      (key: 'return', label: 'Annual Return', isPercentage: true),
      (key: 'volatility', label: 'Volatility', isPercentage: true),
      (key: 'cagr', label: 'CAGR', isPercentage: true),
      (key: 'alpha', label: 'Alpha', isPercentage: true),
      (key: 'beta', label: 'Beta', isPercentage: false),
      (key: 'sortino', label: 'Sortino', isPercentage: false),
    ];

    for (final definition in metricDefinitions) {
      final value = data[definition.key];
      if (value is num) {
        metrics.add(
          MapEntry(
            definition.label,
            definition.isPercentage ? percentage(value) : ratio(value),
          ),
        );
      }
    }

    return metrics;
  }

  void _confirmDelete(BuildContext context, DocumentReference ref) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Delete Portfolio?"),
        content: const Text("This action cannot be undone."),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel"),
          ),
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
    final String typeVisning = _portfolioType(data);
    final weights = Map<String, dynamic>.from(data['weights'] as Map);
    final rawRuns = data['rebalance_runs'];
    final rebalanceHistory = rawRuns is Iterable
        ? rawRuns.map((run) => Map<String, dynamic>.from(run as Map)).toList()
        : <Map<String, dynamic>>[];
    final metrics = _portfolioMetrics(data);

    String pct(dynamic value) {
      if (value is! num) return "N/A";
      return "${(value.toDouble() * 100).toStringAsFixed(1)}%";
    }

    List<Widget> allocationRows(Map<String, dynamic> rowWeights) {
      final entries = rowWeights.entries.toList()
        ..sort((a, b) => (b.value as num).compareTo(a.value as num));

      return entries.map((e) {
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 4.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(e.key, style: const TextStyle(fontWeight: FontWeight.bold)),
              Text(
                "${((e.value as num).toDouble() * 100).toStringAsFixed(1)}%",
              ),
            ],
          ),
        );
      }).toList();
    }

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text("Distribution: $typeVisning"),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (metrics.isNotEmpty) ...[
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      "Performance",
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                  ),
                  const SizedBox(height: 8),
                  ...metrics.map(
                    (metric) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(metric.key),
                          Text(
                            metric.value,
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const Divider(height: 24),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      "Allocation",
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                  ),
                  const SizedBox(height: 4),
                ],
                ...allocationRows(weights),
                if (rebalanceHistory.isNotEmpty) ...[
                  const Divider(height: 24),
                  ...rebalanceHistory.map((run) {
                    final runWeights = run['weights'] is Map
                        ? Map<String, dynamic>.from(run['weights'] as Map)
                        : <String, dynamic>{};

                    return ExpansionTile(
                      tilePadding: EdgeInsets.zero,
                      childrenPadding: const EdgeInsets.only(bottom: 8),
                      title: Text(
                        "Run ${run['number']}: ${run['rebalanced'] == true ? 'Rebalanced' : 'Kept'}",
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      subtitle: Text(
                        "Train ${run['training_start_date']} - ${run['training_end_date']}\n"
                        "Apply ${run['start_date']} - ${run['end_date']} | Return ${pct(run['return'])}",
                        style: const TextStyle(fontSize: 11),
                      ),
                      children: allocationRows(runWeights),
                    );
                  }),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Close"),
          ),
        ],
      ),
    );
  }
}
