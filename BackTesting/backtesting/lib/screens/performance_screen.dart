import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:fl_chart/fl_chart.dart';

class PerformanceScreen extends StatefulWidget {
  const PerformanceScreen({super.key});

  @override
  State<PerformanceScreen> createState() => _PerformanceScreenState();
}

class _PerformanceScreenState extends State<PerformanceScreen> {
  String? _selectedPortfolioId;
  Map<String, dynamic>? _selectedPortfolioData;
  String _selectedTimeframe = '1Y';

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text("Compare Performance"),
      ),
      body: user == null
          ? const Center(child: Text("Please log in to view performance."))
          : Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                children: [
                  // DROPDOWN HENTET FRA FIRESTORE
                  StreamBuilder<QuerySnapshot>(
                    stream: FirebaseFirestore.instance
                        .collection('users')
                        .doc(user.uid)
                        .collection('saved_portfolios')
                        .orderBy('timestamp', descending: true)
                        .snapshots(),
                    builder: (context, snapshot) {
                      if (snapshot.hasError) return const Text("Error loading portfolios");
                      if (!snapshot.hasData) return const CircularProgressIndicator();

                      final docs = snapshot.data!.docs;

                      if (docs.isEmpty) {
                        return const Text("No saved portfolios found.");
                      }

                      return DropdownButtonFormField<String>(
                        decoration: const InputDecoration(
                          labelText: 'Select Saved Portfolio',
                          border: OutlineInputBorder(),
                        ),
                        // Vi binder værdien til ID (String), ikke hele mappet
                        value: _selectedPortfolioId,
                        items: docs.map((doc) {
                          final data = doc.data() as Map<String, dynamic>;
                          return DropdownMenuItem<String>(
                            value: doc.id,
                            child: Text("${data['type']}: ${data['tickers'].join(', ')}"),
                          );
                        }).toList(),
                        onChanged: (String? newId) {
                          setState(() {
                            _selectedPortfolioId = newId;
                            // Find dataen i listen baseret på det valgte ID
                            final selectedDoc = docs.firstWhere((doc) => doc.id == newId);
                            _selectedPortfolioData = selectedDoc.data() as Map<String, dynamic>;
                          });
                        },
                      );
                    },
                  ),
                  
                  const SizedBox(height: 24),

                  // TIDSHORISONT SELECTOR
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: ['1M', '6M', '1Y', '5Y'].map((time) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4.0),
                        child: ChoiceChip(
                          label: Text(time),
                          selected: _selectedTimeframe == time,
                          onSelected: (selected) {
                            if (selected) setState(() => _selectedTimeframe = time);
                          },
                        ),
                      );
                    }).toList(),
                  ),

                  const SizedBox(height: 32),

                  // VISUALISERING AF EQUITY CURVE
                  Expanded(
                    child: _selectedPortfolioData == null
                        ? const Center(child: Text("Select a portfolio to generate the equity curve comparison."))
                        : LineChart(
                            LineChartData(
                              gridData: const FlGridData(show: false),
                              titlesData: const FlTitlesData(show: true),
                              borderData: FlBorderData(show: true),
                              lineBarsData: [
                                // Portefølje Graf (Demo Spots)
                                LineChartBarData(
                                  spots: const [
                                    FlSpot(0, 100),
                                    FlSpot(1, 105),
                                    FlSpot(2, 103),
                                    FlSpot(3, 112),
                                  ],
                                  isCurved: true,
                                  color: theme.colorScheme.primary,
                                  barWidth: 4,
                                  dotData: const FlDotData(show: false),
                                ),
                                // S&P 500 Benchmark (Demo Spots)
                                LineChartBarData(
                                  spots: const [
                                    FlSpot(0, 100),
                                    FlSpot(1, 102),
                                    FlSpot(2, 106),
                                    FlSpot(3, 109),
                                  ],
                                  isCurved: true,
                                  color: Colors.orange,
                                  barWidth: 2,
                                  dashArray: [5, 5],
                                  dotData: const FlDotData(show: false),
                                ),
                              ],
                            ),
                          ),
                  ),

                  // LEGENDE
                  if (_selectedPortfolioData != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 16.0),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          _LegendItem(color: theme.colorScheme.primary, label: 'Portfolio'),
                          const SizedBox(width: 20),
                          const _LegendItem(color: Colors.orange, label: 'S&P 500 (SPY)'),
                        ],
                      ),
                    ),
                ],
              ),
            ),
    );
  }
}

class _LegendItem extends StatelessWidget {
  final Color color;
  final String label;
  const _LegendItem({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(width: 12, height: 12, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 8),
        Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
      ],
    );
  }
}