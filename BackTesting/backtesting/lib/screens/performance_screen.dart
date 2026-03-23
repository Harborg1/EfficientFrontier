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
  
  // Benchmark state
  String _selectedBenchmark = 'SPY';
  final List<String> _benchmarks = ['SPY', 'QQQ', 'DIA', 'IWM'];

  // Statistikker fra backend (Backtest)
  Map<String, dynamic>? _portfolioStats;
  Map<String, dynamic>? _benchmarkStats;

  List<FlSpot> _portfolioSpots = [];
  List<FlSpot> _benchmarkSpots = [];
  bool _isLoading = false;

  // Simulation data
  Map<String, List<FlSpot>> _simulationPaths = {};
  Map<String, dynamic>? _riskMetrics;
  bool _isSimulating = false;

  // --- API KALD TIL BACKEND (Backtest - Out of Sample) ---
  Future<void> _fetchBacktestData() async {
    if (_selectedPortfolioData == null) return;

    setState(() => _isLoading = true);

    // 1. Definer vores Out-of-Sample Test periode.
    // Træningen stoppede ved 'train_end_date', så testen starter der og går frem til i dag.
    final String testStartDate = _selectedPortfolioData!['train_end_date'];
    final DateTime today = DateTime.now();
    final String testEndDate = "${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}";

    final url = Uri.parse('https://efficientfrontier.onrender.com/backtest');

    try {
      final response = await http.post(
        url,
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "tickers": _selectedPortfolioData!['tickers'],
          "weights": _selectedPortfolioData!['weights'],
          "test_start_date": testStartDate, 
          "test_end_date": testEndDate,     
          "benchmark": _selectedBenchmark,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        setState(() {
          _portfolioSpots = (data['portfolio'] as List)
              .map((p) => FlSpot((p['x'] as num).toDouble(), (p['y'] as num).toDouble()))
              .toList();

          _benchmarkSpots = (data['benchmark'] as List)
              .map((p) => FlSpot((p['x'] as num).toDouble(), (p['y'] as num).toDouble()))
              .toList();

          _portfolioStats = data['portfolio_stats'];
          _benchmarkStats = data['benchmark_stats'];
        });
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error fetching backtest: $e")));
    } finally {
      setState(() => _isLoading = false);
    }
  }

  // --- API KALD TIL BACKEND (Simulation) ---
  Future<void> _fetchSimulationData() async {
    if (_selectedPortfolioData == null) return;

    setState(() => _isSimulating = true);

    // Simulationen bruger al tilgængelig historik (Både train og test perioden)
    // for at have det bedst mulige grundlag at bygge spåkuglen på.
    final String histStartDate = _selectedPortfolioData!['train_start_date'];
    final DateTime today = DateTime.now();
    final String histEndDate = "${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}";

    final url = Uri.parse('https://efficientfrontier.onrender.com/simulate');

    try {
      final response = await http.post(
        url,
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "tickers": _selectedPortfolioData!['tickers'],
          "weights": _selectedPortfolioData!['weights'],
          "hist_start_date": histStartDate, 
          "hist_end_date": histEndDate,     
          "days_to_sim": 252, // 1 års fremskrivning i spåkuglen
          "simulations": 1000,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final forecast = data['forecast'];

        setState(() {
          _riskMetrics = data['risk_metrics'];
          _simulationPaths = {
            'p95': _mapToSpots(forecast['p95']),
            'p75': _mapToSpots(forecast['p75']),
            'median': _mapToSpots(forecast['median']),
            'p25': _mapToSpots(forecast['p25']),
            'p5': _mapToSpots(forecast['p5']),
          };
        });
      }
    } catch (e) {
      print("Sim error: $e");
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error fetching simulation: $e")));
    } finally {
      setState(() => _isSimulating = false);
    }
  }

  List<FlSpot> _mapToSpots(List<dynamic> values) {
    return values.asMap().entries.map((e) => FlSpot(e.key.toDouble(), (e.value as num).toDouble())).toList();
  }

  // --- BUILD METODE ---
  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final theme = Theme.of(context);

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text("Performance"),
          bottom: const TabBar(
            tabs: [
              Tab(text: "Out-of-Sample Test", icon: Icon(Icons.history)),
              Tab(text: "Fremtid (Prognose)", icon: Icon(Icons.auto_graph)),
            ],
          ),
        ),
        body: user == null
            ? const Center(child: Text("Log ind for at se performance data"))
            : Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    // --- GLOBAL KONTROL ---
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
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'Vælg Portefølje',
                            border: OutlineInputBorder(),
                            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          ),
                          value: _selectedPortfolioId,
                          items: docs.map((doc) {
                            final data = doc.data() as Map<String, dynamic>;
                            // Vi tilføjer datoen i titlen, så brugeren kan se, hvornår den blev trænet til
                            return DropdownMenuItem(
                              value: doc.id,
                              child: Text("${data['type']} (${data['tickers'].length} aktier) - Trænet til: ${data['train_end_date'] ?? 'N/A'}", style: const TextStyle(fontSize: 12)),
                            );
                          }).toList(),
                          onChanged: (id) {
                            setState(() {
                              _selectedPortfolioId = id;
                              _selectedPortfolioData = docs.firstWhere((d) => d.id == id).data() as Map<String, dynamic>;
                            });
                            _fetchBacktestData();
                            _fetchSimulationData();
                          },
                        );
                      },
                    ),

                    const SizedBox(height: 24),

                    // --- TAB BAR VIEW ---
                    Expanded(
                      child: TabBarView(
                        physics: const NeverScrollableScrollPhysics(),
                        children: [
                          
                          // ==========================================
                          // TAB 1: BACKTEST (Out-of-Sample)
                          // ==========================================
                          Column(
                            children: [
                              const SizedBox(height: 16),
                              // Vi har fjernet Timeframe, da det nu dikteres af test-perioden
                              DropdownButtonFormField<String>(
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
                              const SizedBox(height: 16),
                              
                              if (_portfolioStats != null && !_isLoading) _buildStatsTable(theme),
                              const SizedBox(height: 16),
                              
                              Expanded(
                                child: _isLoading
                                    ? const Center(child: CircularProgressIndicator())
                                    : _portfolioSpots.isEmpty
                                        ? const Center(child: Text("Vælg en portefølje for at køre out-of-sample test"))
                                        : LineChart(_buildChartData(theme)),
                              ),
                              if (_portfolioSpots.isNotEmpty) _buildLegend(theme),
                            ],
                          ),

                          // ==========================================
                          // TAB 2: SIMULATION (Fremtid)
                          // ==========================================
                          Column(
                            children: [
                              if (_riskMetrics != null && !_isSimulating) _buildRiskMetricsBar(theme),
                              const SizedBox(height: 24),
                              
                              Expanded(
                                child: _isSimulating
                                    ? const Center(child: CircularProgressIndicator())
                                    : _simulationPaths.isEmpty
                                        ? const Center(child: Text("Vælg en portefølje for at se prognose"))
                                        : _buildSimulationChart(theme),
                              ),
                              if (_simulationPaths.isNotEmpty) _buildSimulationLegend(theme),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }

  // ==========================================
  // WIDGETS TIL BACKTEST (TAB 1)
  // ==========================================
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
            _statItem("Volatilitet", "${_portfolioStats?['volatility']}%", "${_benchmarkStats?['volatility']}%"),
            _statItem("Afkast", "${_portfolioStats?['perf']}%", "${_benchmarkStats?['perf']}%"),
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
          spots: _benchmarkSpots,
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

  // ==========================================
  // WIDGETS TIL SIMULATION (TAB 2)
  // ==========================================
  Widget _buildRiskMetricsBar(ThemeData theme) {
    return Card(
      elevation: 0,
      color: theme.colorScheme.surfaceVariant.withOpacity(0.3),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _simStatItem("Tabsrisiko (1 år)", "${_riskMetrics!['prob_of_loss_percent']}%", Colors.redAccent),
            _simStatItem("Forventet slutkurs", "${_riskMetrics!['expected_final_value']}", Colors.green),
            _simStatItem("CVaR (Værste 5%)", "${_riskMetrics!['worst_case_cvar_5pct']}", Colors.deepOrange),
          ],
        ),
      ),
    );
  }

  Widget _simStatItem(String label, String value, Color color) {
    return Column(
      children: [
        Text(label, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
        const SizedBox(height: 4),
        Text(value, style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: color)),
      ],
    );
  }

  LineChartBarData _simLayer({required List<FlSpot> spots, required Color color, double width = 0, bool fill = true, List<FlSpot>? belowSpots}) {
    return LineChartBarData(
      spots: spots,
      isCurved: true,
      color: color,
      barWidth: width,
      dotData: const FlDotData(show: false),
      belowBarData: BarAreaData(
        show: fill,
        color: color,
      ),
    );
  }

  Widget _buildSimulationChart(ThemeData theme) {
    return LineChart(
      LineChartData(
        lineBarsData: [
          _simLayer(spots: _simulationPaths['p75']!, color: theme.colorScheme.primary.withOpacity(0.25)),
          _simLayer(spots: _simulationPaths['p25']!, color: Theme.of(context).scaffoldBackgroundColor, fill: true),
          _simLayer(spots: _simulationPaths['p95']!, color: theme.colorScheme.primary.withOpacity(0.1)),
          _simLayer(spots: _simulationPaths['p5']!, color: Theme.of(context).scaffoldBackgroundColor, fill: true),
          _simLayer(spots: _simulationPaths['median']!, color: theme.colorScheme.primary, width: 3, fill: false),
        ],
        gridData: FlGridData(show: true, drawVerticalLine: false, getDrawingHorizontalLine: (v) => FlLine(color: Colors.grey.withOpacity(0.1), strokeWidth: 1)),
        titlesData: FlTitlesData(
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          bottomTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 40, getTitlesWidget: (v, m) => Text(v.toInt().toString(), style: const TextStyle(fontSize: 10)))),
        ),
        borderData: FlBorderData(show: true, border: Border.all(color: Colors.grey.withOpacity(0.2))),
        lineTouchData: const LineTouchData(enabled: false), 
      ),
    );
  }

  Widget _buildSimulationLegend(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _legendCircle(theme.colorScheme.primary, "Median"),
          const SizedBox(width: 15),
          _legendCircle(theme.colorScheme.primary.withOpacity(0.3), "Sandsynlig (50%)"),
          const SizedBox(width: 15),
          _legendCircle(theme.colorScheme.primary.withOpacity(0.1), "Ekstrem (90%)"),
        ],
      ),
    );
  }

  Widget _legendCircle(Color color, String label) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Container(width: 12, height: 12, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
      const SizedBox(width: 6),
      Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
    ]);
  }
}