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
  
  List<FlSpot> _portfolioSpots = [];
  List<FlSpot> _spySpots = [];
  
  Map<String, dynamic>? _portfolioStats;
  Map<String, dynamic>? _spyStats;
  
  bool _isLoading = false;

  Future<void> _fetchBacktestData() async {
    if (_selectedPortfolioData == null) return;

    setState(() {
      _isLoading = true;
      _portfolioSpots = [];
      _spySpots = [];
      _portfolioStats = null;
      _spyStats = null;
    });

    final url = Uri.parse('https://efficientfrontier.onrender.com/backtest'); 
    
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

          _portfolioStats = data['portfolio_stats'];
          _spyStats = data['spy_stats'];
        });
      } else {
        throw Exception("Server returned ${response.statusCode}");
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Could not fetch data: $e")),
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text("Performance Analysis")),
      body: user == null
          ? const Center(child: Text("Please log in to view performance data."))
          : Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // 1. Dropdown
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
                      if (docs.isEmpty) return const Text("No saved portfolios found.");

                      return DropdownButtonFormField<String>(
                        decoration: const InputDecoration(
                          labelText: 'Choose Portfolio', 
                          border: OutlineInputBorder()
                        ),
                        value: _selectedPortfolioId,
                        items: docs.map((doc) {
                          final data = doc.data() as Map<String, dynamic>;
                          return DropdownMenuItem(
                            value: doc.id,
                            child: Text("${data['type']} (${data['tickers'].length} assets)"),
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

                  const SizedBox(height: 16),

                  // 2. Timeframe chips
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

                  const SizedBox(height: 24),

                  // 3. Chart (Expanded to take available space)
                  Expanded(
                    child: _isLoading 
                      ? const Center(child: CircularProgressIndicator())
                      : _portfolioSpots.isEmpty 
                        ? const Center(child: Text("Choose a portfolio to compare against the SPY"))
                        : LineChart(_buildChartData(theme)),
                  ),

                  if (_portfolioSpots.isNotEmpty) _buildLegend(theme),

                  const SizedBox(height: 24),

                  // 4. Statistics Table (Removed Expanded to prevent RenderFlex error)
                  if (_portfolioStats != null && _spyStats != null)
                    _buildStatsTable(theme),
                ],
              ),
            ),
    );
  }

  Widget _buildStatsTable(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceVariant.withOpacity(0.3),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min, // Wrap content tightly
        children: [
          _statHeader(),
          const Divider(),
          _statRow("Sharpe Ratio", _portfolioStats!['sharpe'], _spyStats!['sharpe'], higherIsBetter: true),
          _statRow("Volatility", "${_portfolioStats!['volatility']}%", "${_spyStats!['volatility']}%", higherIsBetter: false, rawPort: _portfolioStats!['volatility'], rawSpy: _spyStats!['volatility']),
          _statRow("Max Drawdown", "${_portfolioStats!['max_drawdown']}%", "${_spyStats!['max_drawdown']}%", higherIsBetter: false, rawPort: _portfolioStats!['max_drawdown'], rawSpy: _spyStats!['max_drawdown']),
          _statRow("Cumulative Return", "${_portfolioStats!['ytd_perf']}%", "${_spyStats!['ytd_perf']}%", higherIsBetter: true),
        ],
      ),
    );
  }

  Widget _statHeader() {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        children: [
          Expanded(flex: 2, child: Text("Metric", style: TextStyle(fontWeight: FontWeight.bold))),
          Expanded(child: Text("Portfolio", textAlign: TextAlign.right, style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue))),
          Expanded(child: Text("S&P 500", textAlign: TextAlign.right, style: TextStyle(fontWeight: FontWeight.bold, color: Colors.orange))),
        ],
      ),
    );
  }

  Widget _statRow(String label, dynamic port, dynamic spy, {required bool higherIsBetter, dynamic rawPort, dynamic rawSpy}) {
    bool isWinner = false;
    final valP = rawPort ?? port;
    final valS = rawSpy ?? spy;
    
    if (higherIsBetter) {
      isWinner = valP > valS;
    } else {
      isWinner = valP < valS;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        children: [
          Expanded(flex: 2, child: Text(label, style: const TextStyle(fontSize: 13))),
          Expanded(
            child: Text(
              port.toString(), 
              textAlign: TextAlign.right, 
              style: TextStyle(
                fontWeight: FontWeight.bold, 
                color: isWinner ? Colors.green : Colors.redAccent
              )
            )
          ),
          Expanded(
            child: Text(
              spy.toString(), 
              textAlign: TextAlign.right, 
              style: const TextStyle(color: Colors.grey)
            )
          ),
        ],
      ),
    );
  }

  LineChartData _buildChartData(ThemeData theme) {
    return LineChartData(
      lineTouchData: LineTouchData(
        touchTooltipData: LineTouchTooltipData(
          getTooltipColor: (spot) => Colors.blueGrey.withOpacity(0.9),
          getTooltipItems: (spots) => spots.map((s) => LineTooltipItem(
            "Value: ${s.y.toStringAsFixed(2)}", 
            const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)
          )).toList(),
        ),
      ),
      gridData: FlGridData(
        show: true, 
        drawVerticalLine: false,
        getDrawingHorizontalLine: (v) => FlLine(color: Colors.grey.withOpacity(0.1), strokeWidth: 1)
      ),
      titlesData: const FlTitlesData(
        rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
        topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
        bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
        leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 45)),
      ),
      borderData: FlBorderData(show: false),
      lineBarsData: [
        LineChartBarData(
          spots: _portfolioSpots,
          isCurved: true,
          color: theme.colorScheme.primary,
          barWidth: 4,
          dotData: const FlDotData(show: false),
          belowBarData: BarAreaData(show: true, color: theme.colorScheme.primary.withOpacity(0.1)),
        ),
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
      padding: const EdgeInsets.only(top: 8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _legendItem(theme.colorScheme.primary, "Your Portfolio"),
          const SizedBox(width: 20),
          _legendItem(Colors.orange, "S&P 500 (SPY)"),
        ],
      ),
    );
  }

  Widget _legendItem(Color color, String label) {
    return Row(children: [
      Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
      const SizedBox(width: 6),
      Text(label, style: const TextStyle(fontSize: 12)),
    ]);
  }
}