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
  String _selectedTimeframe = '1y';
  
  // Benchmark state
  String _selectedBenchmark = 'SPY';
  final List<String> _benchmarks = ['SPY', 'QQQ', 'DIA', 'IWM'];

  // Statistikker fra backend
  Map<String, dynamic>? _portfolioStats;
  Map<String, dynamic>? _benchmarkStats;

  List<FlSpot> _portfolioSpots = [];
  List<FlSpot> _benchmarkSpots = []; 
  bool _isLoading = false;

  // --- API KALD TIL BACKEND ---
  Future<void> _fetchBacktestData() async {
    if (_selectedPortfolioData == null) return;

    setState(() => _isLoading = true);

    final url = Uri.parse('https://efficientfrontier.onrender.com/backtest'); 
    
    try {
      final response = await http.post(
        url,
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "tickers": _selectedPortfolioData!['tickers'],
          "weights": _selectedPortfolioData!['weights'],
          "timeframe": _selectedTimeframe.toLowerCase(),
          "benchmark": _selectedBenchmark, // Sender den valgte benchmark
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        
        setState(() {
          // Opdater graf-punkter
          _portfolioSpots = (data['portfolio'] as List)
              .map((p) => FlSpot((p['x'] as num).toDouble(), (p['y'] as num).toDouble()))
              .toList();
          
          // Her bruger vi nu kun 'benchmark' nøglen fra din nye backend
          _benchmarkSpots = (data['benchmark'] as List)
              .map((p) => FlSpot((p['x'] as num).toDouble(), (p['y'] as num).toDouble()))
              .toList();

          // Opdater statistikker
          _portfolioStats = data['portfolio_stats'];
          _benchmarkStats = data['benchmark_stats'];
        });
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error fetching data: $e")));
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text("Performance")),
      body: user == null
          ? const Center(child: Text("Log ind for at se performance data"))
          : Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                children: [
                  // SELECTOR ROW (Portfolio & Benchmark)
                  Row(
                    children: [
                      Expanded(
                        flex: 3,
                        child: StreamBuilder<QuerySnapshot>(
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
                              isExpanded: true,
                              decoration: const InputDecoration(
                                labelText: 'Portefølje', 
                                border: OutlineInputBorder(),
                                contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              ),
                              value: _selectedPortfolioId,
                              items: docs.map((doc) {
                                final data = doc.data() as Map<String, dynamic>;
                                return DropdownMenuItem(
                                  value: doc.id,
                                  child: Text("${data['type']} (${data['tickers'].length} aktier)", style: const TextStyle(fontSize: 13)),
                                );
                              }).toList(),
                              onChanged: (id) {
                                setState(() {
                                  _selectedPortfolioId = id;
                                  _selectedPortfolioData = docs.firstWhere((d) => d.id == id).data() as Map<String, dynamic>;
                                });
                                _fetchBacktestData();
                              },
                            );
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 2,
                        child: DropdownButtonFormField<String>(
                          decoration: const InputDecoration(
                            labelText: 'Benchmark', 
                            border: OutlineInputBorder(),
                            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          ),
                          value: _selectedBenchmark,
                          items: _benchmarks.map((ticker) => DropdownMenuItem(value: ticker, child: Text(ticker))).toList(),
                          onChanged: (val) {
                            if (val != null) {
                              setState(() => _selectedBenchmark = val);
                              _fetchBacktestData();
                            }
                          },
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 16),

                  // TIMEFRAME SELECTOR
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: ['1m', '6m', '1år', '5år', 'max'].map((time) {
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

                  const SizedBox(height: 24),

                  // STATS TABLE (Valgfrit, men anbefalet da din backend nu sender det)
                  if (_portfolioStats != null && !_isLoading) _buildStatsTable(theme),

                  const SizedBox(height: 24),

                  // GRAF SEKTION
                  Expanded(
                    child: _isLoading 
                      ? const Center(child: CircularProgressIndicator())
                      : _portfolioSpots.isEmpty 
                        ? const Center(child: Text("Vælg en portefølje for at sammenligne med benchmark"))
                        : LineChart(_buildChartData(theme)),
                  ),

                  if (_portfolioSpots.isNotEmpty) _buildLegend(theme),
                ],
              ),
            ),
    );
  }

  // Ny hjælpe-widget til at vise statistikkerne fra backenden
  Widget _buildStatsTable(ThemeData theme) {
    return Card(
      elevation: 0,
      color: theme.colorScheme.surfaceVariant.withOpacity(0.3),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _statItem("Sharpe", _portfolioStats?['sharpe'], _benchmarkStats?['sharpe']),
            _statItem("Vol", "${_portfolioStats?['volatility']}%", "${_benchmarkStats?['volatility']}%"),
            _statItem("Return", "${_portfolioStats?['perf']}%", "${_benchmarkStats?['perf']}%"),
          ],
        ),
      ),
    );
  }

  Widget _statItem(String label, dynamic portVal, dynamic benchVal) {
    return Column(
      children: [
        Text(label, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
        const SizedBox(height: 4),
        Text("P: $portVal", style: TextStyle(color: Theme.of(context).colorScheme.primary, fontSize: 11)),
        Text("B: $benchVal", style: const TextStyle(color: Colors.orange, fontSize: 11)),
      ],
    );
  }

  // ... (Resten af dine metoder: _buildChartData, _buildLegend, _legendCircle er uændrede)
  // Men husk at bruge _benchmarkSpots i _buildChartData i stedet for _spySpots.
  
  LineChartData _buildChartData(ThemeData theme) {
    return LineChartData(
      lineTouchData: LineTouchData(
        touchTooltipData: LineTouchTooltipData(
          getTooltipColor: (LineBarSpot touchedSpot) => Colors.blueGrey.withOpacity(0.8),
          tooltipRoundedRadius: 8,
          getTooltipItems: (List<LineBarSpot> touchedSpots) {
            return touchedSpots.map((LineBarSpot touchedSpot) {
              return LineTooltipItem(
                touchedSpot.y.toStringAsFixed(2),
                const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              );
            }).toList();
          },
        ),
      ),
      gridData: FlGridData(show: true, drawVerticalLine: false, getDrawingHorizontalLine: (v) => FlLine(color: Colors.grey.withOpacity(0.1), strokeWidth: 1)),
      titlesData: FlTitlesData(
        rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        bottomTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 40, getTitlesWidget: (v, m) => Text(v.toInt().toString(), style: const TextStyle(fontSize: 10)))),
      ),
      borderData: FlBorderData(show: true, border: Border.all(color: Colors.grey.withOpacity(0.2))),
      lineBarsData: [
        LineChartBarData(
          spots: _portfolioSpots,
          isCurved: true,
          color: theme.colorScheme.primary,
          barWidth: 3,
          dotData: const FlDotData(show: false),
          belowBarData: BarAreaData(show: true, color: theme.colorScheme.primary.withOpacity(0.1)),
        ),
        LineChartBarData(
          spots: _benchmarkSpots, // Opdateret variabelnavn
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
          _legendCircle(theme.colorScheme.primary, "Din portefølje"),
          const SizedBox(width: 20),
          _legendCircle(Colors.orange, _selectedBenchmark),
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