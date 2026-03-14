import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

class PerformanceScreen extends StatefulWidget {
  const PerformanceScreen({super.key});

  @override
  State<PerformanceScreen> createState() => _PerformanceScreenState();
}

class _PerformanceScreenState extends State<PerformanceScreen> {
  String? _selectedPortfolioId;
  Map<String, dynamic>? _selectedPortfolioData;
  String _selectedTimeframe = '1y'; // Backend forventer små bogstaver: 1y, 5y osv.
  
  List<FlSpot> _portfolioSpots = [];
  List<FlSpot> _spySpots = [];
  bool _isLoading = false;

  // --- API KALD TIL BACKEND ---
  Future<void> _fetchBacktestData() async {
    if (_selectedPortfolioData == null) return;

    setState(() => _isLoading = true);

    final url = Uri.parse('https://efficientfrontier.onrender.com/backtest'); // Ret til din URL
    
    try {
      final response = await http.post(
        url,
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "tickers": _selectedPortfolioData!['tickers'],
          "weights": _selectedPortfolioData!['weights'],
          "timeframe": _selectedTimeframe.toLowerCase(),
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        
        setState(() {
          _portfolioSpots = (data['portfolio'] as List)
              .map((p) => FlSpot((p['x'] as num).toDouble(), (p['y'] as num).toDouble()))
              .toList();
          
          _spySpots = (data['spy'] as List)
              .map((p) => FlSpot((p['x'] as num).toDouble(), (p['y'] as num).toDouble()))
              .toList();
        });
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error fetching curve: $e")));
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text("Equity Curve Comparison")),
      body: user == null
          ? const Center(child: Text("Log in to see performance"))
          : Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                children: [
                  // DROPDOWN
                  StreamBuilder<QuerySnapshot>(
                    stream: FirebaseFirestore.instance
                        .collection('users')
                        .doc(user.uid)
                        .collection('saved_portfolios')
                        .orderBy('timestamp', descending: true)
                        .snapshots(),
                    builder: (context, snapshot) {
                      if (!snapshot.hasData) return const LinearProgressIndicator();
                      final docs = snapshot.data!.docs;

                      return DropdownButtonFormField<String>(
                        decoration: const InputDecoration(labelText: 'Select Portfolio', border: OutlineInputBorder()),
                        value: _selectedPortfolioId,
                        items: docs.map((doc) {
                          final data = doc.data() as Map<String, dynamic>;
                          return DropdownMenuItem(
                            value: doc.id,
                            child: Text("${data['type']} (${data['tickers'].length} stocks)"),
                          );
                        }).toList(),
                        onChanged: (id) {
                          _selectedPortfolioId = id;
                          _selectedPortfolioData = docs.firstWhere((d) => d.id == id).data() as Map<String, dynamic>;
                          _fetchBacktestData();
                        },
                      );
                    },
                  ),

                  const SizedBox(height: 16),

                  // TIMEFRAME SELECTOR
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: ['1mo', '6mo', '1y', '5y', 'max'].map((time) {
                        return Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4.0),
                          child: ChoiceChip(
                            label: Text(time.toUpperCase()),
                            selected: _selectedTimeframe == time,
                            onSelected: (val) {
                              if (val) {
                                setState(() => _selectedTimeframe = time);
                                _fetchBacktestData();
                              }
                            },
                          ),
                        );
                      }).toList(),
                    ),
                  ),

                  const SizedBox(height: 32),

                  // GRAF SEKTION
                  Expanded(
                    child: _isLoading 
                      ? const Center(child: CircularProgressIndicator())
                      : _portfolioSpots.isEmpty 
                        ? const Center(child: Text("Select a portfolio to see historical growth (Base 100)"))
                        : LineChart(_buildChartData(theme)),
                  ),

                  // LEGENDE
                  if (_portfolioSpots.isNotEmpty) _buildLegend(theme),
                ],
              ),
            ),
    );
  }

  LineChartData _buildChartData(ThemeData theme) {
    return LineChartData(
              lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            // HER ER RETTELSEN:
            getTooltipColor: (LineBarSpot touchedSpot) => Colors.blueGrey.withOpacity(0.8),
            tooltipRoundedRadius: 8,
            getTooltipItems: (List<LineBarSpot> touchedSpots) {
              return touchedSpots.map((LineBarSpot touchedSpot) {
                return LineTooltipItem(
                  touchedSpot.y.toStringAsFixed(2),
                  const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                );
              }).toList();
            },
          ),
        ),
      gridData: FlGridData(show: true, drawVerticalLine: false, getDrawingHorizontalLine: (v) => FlLine(color: Colors.grey.withOpacity(0.1), strokeWidth: 1)),
      titlesData: FlTitlesData(
        rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        bottomTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)), // X-aksen er bare index (dage)
        leftTitles: AxisTitles(
          sideTitles: SideTitles(showTitles: true, reservedSize: 40, getTitlesWidget: (v, m) => Text(v.toInt().toString(), style: const TextStyle(fontSize: 10))),
        ),
      ),
      borderData: FlBorderData(show: true, border: Border.all(color: Colors.grey.withOpacity(0.2))),
      lineBarsData: [
        // PORTFOLIO LINE
        LineChartBarData(
          spots: _portfolioSpots,
          isCurved: true,
          color: theme.colorScheme.primary,
          barWidth: 3,
          dotData: const FlDotData(show: false),
          belowBarData: BarAreaData(show: true, color: theme.colorScheme.primary.withOpacity(0.1)),
        ),
        // SPY LINE
        LineChartBarData(
          spots: _spySpots,
          isCurved: true,
          color: Colors.orange,
          barWidth: 2,
          dashArray: [5, 5],
          dotData: const FlDotData(show: false),
        ),
      ],
    );
  }

  Widget _buildLegend(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _legendCircle(theme.colorScheme.primary, "Your Portfolio"),
          const SizedBox(width: 20),
          _legendCircle(Colors.orange, "S&P 500 (SPY)"),
        ],
      ),
    );
  }

  Widget _legendCircle(Color color, String label) {
    return Row(children: [
      Container(width: 12, height: 12, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
      const SizedBox(width: 6),
      Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
    ]);
  }
}