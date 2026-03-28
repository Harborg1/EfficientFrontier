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
  String _selectedTimeframe = 'max';
  String _selectedBenchmark = 'SPY';
  final List<String> _benchmarks = ['SPY', 'QQQ', 'DIA', 'IWM'];

  // Statistikker fra backend (Backtest)
  Map<String, dynamic>? _portfolioStats;
  Map<String, dynamic>? _benchmarkStats;
  double? _portfolioCorrelation;
  String? _correlationPeriod;

  List<FlSpot> _portfolioSpots = [];
  List<FlSpot> _benchmarkSpots = [];
  bool _isLoading = false;
  bool _isCorrelationLoading = false;

  // Simulation data
  Map<String, List<FlSpot>> _simulationPaths = {};
  Map<String, dynamic>? _riskMetrics;
  bool _isSimulating = false;

  String _currentVisibleStartDate = "";

  
  String _formatDateLabel(double value, String? startStr) {
  if (startStr == null) return "";
  try {
    DateTime startDate = DateTime.parse(startStr);
    // Vi ganger med 1.442 for at konvertere handelsdage til kalenderdage
    int daysToAdd = (value * 1.442).toInt(); 
    DateTime date = startDate.add(Duration(days: daysToAdd));
    
    List<String> months = ["Jan", "Feb", "Mar", "Apr", "Maj", "Jun", "Jul", "Aug", "Sep", "Okt", "Nov", "Dec"];
    return "${months[date.month - 1]} ${date.year.toString().substring(2)}";
  } catch (e) {
    return "";
  }
}

  // --- API KALD TIL BACKEND (Backtest - Out of Sample) ---
 // 3. Den rettede API-funktion
Future<void> _fetchBacktestData() async {
  if (_selectedPortfolioData == null) return;

  setState(() {
    _isLoading = true;
    _portfolioSpots = []; // Ryd data så grafen ikke viser gamle datoer mens den loader
  });

  // --- NY DATO-LOGIK: Vi regner baglæns fra i dag ---
  final DateTime today = DateTime.now();
  final DateTime trainEndDate = DateTime.parse(_selectedPortfolioData!['train_end_date']);
  
  DateTime startDateObj;

  switch (_selectedTimeframe) {
    case '1mo': startDateObj = today.subtract(const Duration(days: 30)); break;
    case '6mo': startDateObj = today.subtract(const Duration(days: 182)); break;
    case '1y':  startDateObj = today.subtract(const Duration(days: 365)); break;
    case 'max':
    default:    startDateObj = trainEndDate; break;
  }

  // SIKKERHED: Vi må aldrig gå længere tilbage end der hvor træningen sluttede (Out-of-sample)
  if (startDateObj.isBefore(trainEndDate)) {
    startDateObj = trainEndDate;
  }

  final String finalStartStr = startDateObj.toIso8601String().substring(0, 10);
  final String finalEndStr = today.toIso8601String().substring(0, 10);

  // VIGTIGT: Gem den faktiske startdato for denne visning til brug i tidsaksen
  setState(() {
    _currentVisibleStartDate = finalStartStr;
  });

  final url = Uri.parse('https://efficientfrontier.onrender.com/backtest');

  try {
    final response = await http.post(
      url,
      headers: {"Content-Type": "application/json"},
      body: jsonEncode({
        "tickers": _selectedPortfolioData!['tickers'],
        "weights": _selectedPortfolioData!['weights'],
        "test_start_date": finalStartStr, 
        "test_end_date": finalEndStr,     
        "benchmark": _selectedBenchmark,
      }),
    ).timeout(const Duration(seconds: 90));

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
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
  } finally {
    setState(() => _isLoading = false);
  }
}

  Future<void> _fetchCorrelationData() async {
    if (_selectedPortfolioData == null) return;

    setState(() {
      _isCorrelationLoading = true;
      _portfolioCorrelation = null;
      _correlationPeriod = null;
    });

    final DateTime today = DateTime.now();
    final DateTime trainEndDate = DateTime.parse(_selectedPortfolioData!['train_end_date']);
    DateTime startDateObj;

    switch (_selectedTimeframe) {
      case '1mo':
        startDateObj = today.subtract(const Duration(days: 30));
        break;
      case '6mo':
        startDateObj = today.subtract(const Duration(days: 182));
        break;
      case '1y':
        startDateObj = today.subtract(const Duration(days: 365));
        break;
      case 'max':
      default:
        startDateObj = trainEndDate;
        break;
    }

    if (startDateObj.isBefore(trainEndDate)) {
      startDateObj = trainEndDate;
    }

    final String finalStartStr = startDateObj.toIso8601String().substring(0, 10);
    final String finalEndStr =
        "${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}";

    final url = Uri.parse('https://efficientfrontier.onrender.com/correlation');

    try {
      final response = await http.post(
        url,
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "tickers": _selectedPortfolioData!['tickers'],
          "weights": _selectedPortfolioData!['weights'],
          "test_start_date": finalStartStr,
          "test_end_date": finalEndStr,
        }),
      ).timeout(const Duration(seconds: 90));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          _portfolioCorrelation = (data['portfolio_correlation'] as num?)?.toDouble();
          _correlationPeriod = "${data['period_start']} - ${data['period_end']}";
        });
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error fetching correlation: $e")),
      );
    } finally {
      setState(() => _isCorrelationLoading = false);
    }
  }
  // --- API KALD TIL BACKEND (Simulation) ---
  Future<void> _fetchSimulationData() async {
    if (_selectedPortfolioData == null) return;

    setState(() => _isSimulating = true);

    final String histStartDate = _selectedPortfolioData!['train_start_date'];
    final DateTime today = DateTime.now();
    final String finalEndStr = "${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}";

    final url = Uri.parse('https://efficientfrontier.onrender.com/simulate');

    try {
      final response = await http.post(
        url,
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "tickers": _selectedPortfolioData!['tickers'],
          "weights": _selectedPortfolioData!['weights'],
          "hist_start_date": histStartDate, 
          "hist_end_date": finalEndStr,     
          "days_to_sim": 252, // 1 års fremskrivning i spåkuglen
          "simulations": 1000,
        }),
      ).timeout(const Duration(seconds:90));

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
                    // --- GLOBAL KONTROL: Valg af portefølje ---
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
                            return DropdownMenuItem(
                              value: doc.id,
                              child: Text(
                                "${data['type']} (${data['tickers'].length} aktier) - Trænet: ${data['train_start_date'] ?? 'N/A'}-${data['train_end_date'] ?? 'N/A'}",
                                style: const TextStyle(fontSize: 12),
                              ),
                            );
                          }).toList(),
                          onChanged: (id) {
                            setState(() {
                              _selectedPortfolioId = id;
                              _selectedPortfolioData = docs.firstWhere((d) => d.id == id).data() as Map<String, dynamic>;
                            });
                            _fetchBacktestData();
                            _fetchCorrelationData();
                            _fetchSimulationData();
                          },
                        );
                      },
                    ),

                    const SizedBox(height: 24),

                    _buildCorrelationCard(theme),

                    const SizedBox(height: 16),

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
                              
                              // HER ER DE TO DROPDOWNS SIDE OM SIDE
                              Row(
                                children: [
                                  // Benchmark valg
                                  Expanded(
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
                                  const SizedBox(width: 12),
                                  // Test-længde valg
                                  Expanded(
                                    child: DropdownButtonFormField<String>(
                                      decoration: const InputDecoration(
                                        labelText: 'Test-længde',
                                        border: OutlineInputBorder(),
                                        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                      ),
                                      value: _selectedTimeframe,
                                      items: const [
                                        DropdownMenuItem(value: '1mo', child: Text('1 MD')),
                                        DropdownMenuItem(value: '6mo', child: Text('6 MDR')),
                                        DropdownMenuItem(value: '1y', child: Text('1 ÅR')),
                                        DropdownMenuItem(value: 'max', child: Text('ALT')),
                                      ],
                                      onChanged: (val) {
                                        if (val != null) {
                                          setState(() => _selectedTimeframe = val);
                                          _fetchBacktestData();
                                          _fetchCorrelationData();
                                          _fetchSimulationData();
                                        }
                                      },
                                    ),
                                  ),
                                ],
                              ),
                              
                              const SizedBox(height: 16),
                              
                              if (_portfolioStats != null && !_isLoading) _buildStatsTable(theme),
                              
                              const SizedBox(height: 16),
                              
                              Expanded(
                                child: _isLoading
                                    ? const Center(child: CircularProgressIndicator())
                                    : _portfolioSpots.isEmpty
                                        ? const Center(child: Text("Vælg en portefølje for at se backtest"))
                                        : _buildSlightlyWiderChart(
                                            LineChart(_buildChartData(theme)),
                                          ),
                              ),
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

  Widget _buildCorrelationCard(ThemeData theme) {
    return Card(
      elevation: 0,
      color: theme.colorScheme.surfaceVariant.withOpacity(0.3),
      child: Padding(
        padding: const EdgeInsets.all(14.0),
        child: Row(
          children: [
            Icon(Icons.hub_outlined, color: theme.colorScheme.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "Porteføljekorrelation",
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _isCorrelationLoading
                        ? "Beregner korrelation..."
                        : _portfolioCorrelation == null
                            ? "Ingen korrelation tilgængelig"
                            : _portfolioCorrelation!.toStringAsFixed(3),
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                  if (_correlationPeriod != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      _correlationPeriod!,
                      style: TextStyle(fontSize: 11, color: Colors.blueGrey.shade600),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

LineChartData _buildChartData(ThemeData theme) {
  // Find det sidste punkt på x-aksen for at kunne give grafen lidt luft til højre
  double maxXValue = _portfolioSpots.isNotEmpty ? _portfolioSpots.last.x : 0;

  return LineChartData(
    // 1. BUFFER: Vi giver grafen 5% ekstra plads til højre, så den ikke rammer kanten
    maxX: maxXValue > 0 ? maxXValue * 1.1 : null,
    
    // CLIP DATA: Sørger for at linjerne bliver inde i rammen
    clipData: const FlClipData.all(),
    
    lineTouchData: LineTouchData(
      touchTooltipData: LineTouchTooltipData(
        getTooltipColor: (LineBarSpot touchedSpot) => Colors.blueGrey.withOpacity(0.8),
        tooltipRoundedRadius: 8,
        
        // --- HER ER FIXET TIL DRAG/TOOLTIP ---
        fitInsideHorizontally: true, // Spejlvender boksen hvis den rammer højre kant
        fitInsideVertically: true,   // Holder boksen indenfor top/bund
        // -------------------------------------

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
    
    // ... resten af dine gridData, titlesData, borderData og lineBarsData herunder

    // 2. GRID: Vi tilføjer meget svage vertikale linjer for at hjælpe øjet
    gridData: FlGridData(
      show: true, 
      drawVerticalLine: true, // Nu med vertikale linjer
      getDrawingHorizontalLine: (v) => FlLine(color: Colors.grey.withOpacity(0.05), strokeWidth: 1),
      getDrawingVerticalLine: (v) => FlLine(color: Colors.grey.withOpacity(0.05), strokeWidth: 1),
    ),

    titlesData: FlTitlesData(
      rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      
      // 3. VENSTRE AKSE: Mere moderne look
      leftTitles: AxisTitles(
        sideTitles: SideTitles(
          showTitles: false,
          reservedSize: 0,
        ),
      ),

      // 4. BUND AKSE DATOER
        bottomTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 32,
            interval: 64, // Viser en label ca. hver 3. måned
            getTitlesWidget: (value, meta) {
              // Skjul labels i kanten for at undgå at de bliver mast
              if (value == meta.min || value == meta.max) return const SizedBox.shrink();
              
              return SideTitleWidget(
                meta: meta,
                space: 8,
                child: Text(
                  // Her bruger vi din nye dynamiske startdato!
                  _formatDateLabel(value, _currentVisibleStartDate), 
                  style: TextStyle(
                    fontSize: 10, 
                    fontWeight: FontWeight.w500, 
                    color: Colors.blueGrey.shade600
                  ),
                ),
              );
            },
          ),
        ),
      ),

    borderData: FlBorderData(
      show: true, 
      border: Border(
        bottom: BorderSide(color: Colors.grey.withOpacity(0.2)),
        left: BorderSide(color: Colors.grey.withOpacity(0.2)),
      ),
    ),

    lineBarsData: [
      LineChartBarData(
        spots: _portfolioSpots,
        isCurved: true,
        color: theme.colorScheme.primary,
        barWidth: 3,
        dotData: const FlDotData(show: false),
        belowBarData: BarAreaData(show: true, color: theme.colorScheme.primary.withOpacity(0.05)),
      ),
      LineChartBarData(
        spots: _benchmarkSpots,
        isCurved: true,
        color: Colors.orange.withOpacity(0.7), // Gør benchmark lidt mere diskret
        barWidth: 2,
        dashArray: [5, 5],
        dotData: const FlDotData(show: false),
      ),
    ],
  );
}
  // ==========================================
  // WIDGETS TIL SIMULATION (TAB 2)
  // ==========================================

  LineChartData _buildSimulationChartData(ThemeData theme) {
  // Find det sidste punkt for at give grafen luft til højre (buffer)
  double maxXValue = 0;
  if (_simulationPaths.containsKey('median') && _simulationPaths['median']!.isNotEmpty) {
    maxXValue = _simulationPaths['median']!.last.x;
  }

  // Vi definerer dags dato som startpunkt for tidsaksen i prognosen
  final String todayStr = DateTime.now().toIso8601String().substring(0, 10);

  return LineChartData(
    // 1. BUFFER & CLIP: Giver 10% luft til højre og holder data indenfor rammen
    maxX: maxXValue > 0 ? maxXValue * 1.1 : null,
    clipData: const FlClipData.all(),

    // 2. TOOLTIP FIX: Sørger for at boksene ikke forsvinder ved kanterne
    lineTouchData: LineTouchData(
      touchTooltipData: LineTouchTooltipData(
        getTooltipColor: (spot) => Colors.blueGrey.withOpacity(0.8),
        fitInsideHorizontally: true,
        fitInsideVertically: true,
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

    // 3. GRID: Svage linjer der matcher backtesten
    gridData: FlGridData(
      show: true,
      drawVerticalLine: true,
      getDrawingHorizontalLine: (v) => FlLine(color: Colors.grey.withOpacity(0.05), strokeWidth: 1),
      getDrawingVerticalLine: (v) => FlLine(color: Colors.grey.withOpacity(0.05), strokeWidth: 1),
    ),

    // 4. TITLES: SideTitleWidget for et skarpt look
    titlesData: FlTitlesData(
      rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      
      leftTitles: AxisTitles(
        sideTitles: SideTitles(
          showTitles: false,
          reservedSize: 0,
        ),
      ),

      bottomTitles: AxisTitles(
        sideTitles: SideTitles(
          showTitles: true,
          reservedSize: 32,
          interval: 64, // Viser dato ca. hver 3. måned
          getTitlesWidget: (value, meta) {
            if (value == meta.min || value == meta.max) return const SizedBox.shrink();

            return SideTitleWidget(
              meta: meta,
              space: 8,
              child: Text(
                _formatDateLabel(value, todayStr),
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w500,
                  color: Colors.blueGrey.shade600,
                ),
              ),
            );
          },
        ),
      ),
    ),

    borderData: FlBorderData(
      show: true,
      border: Border(
        bottom: BorderSide(color: Colors.grey.withOpacity(0.2)),
        left: BorderSide(color: Colors.grey.withOpacity(0.2)),
      ),
    ),

    // 5. DATA LAG (Viften)
    lineBarsData: [
      _simLayer(spots: _simulationPaths['p75']!, color: theme.colorScheme.primary.withOpacity(0.25)),
      _simLayer(spots: _simulationPaths['p25']!, color: theme.scaffoldBackgroundColor, fill: true),
      _simLayer(spots: _simulationPaths['p95']!, color: theme.colorScheme.primary.withOpacity(0.1)),
      _simLayer(spots: _simulationPaths['p5']!, color: theme.scaffoldBackgroundColor, fill: true),
      _simLayer(spots: _simulationPaths['median']!, color: theme.colorScheme.primary, width: 3, fill: false),
    ],
  );
}
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
  if (_simulationPaths.isEmpty) return const Center(child: Text("Ingen simuleringsdata"));

  return _buildSlightlyWiderChart(
    LineChart(
      _buildSimulationChartData(theme),
    ),
  );
}

  Widget _buildSlightlyWiderChart(Widget chart) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return OverflowBox(
          minWidth: constraints.maxWidth,
          maxWidth: constraints.maxWidth,
          alignment: Alignment.center,
          child: SizedBox(
            width: constraints.maxWidth,
            child: chart,
          ),
        );
      },
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
          _legendCircle(theme.colorScheme.primary.withOpacity(0.6), "Sandsynlig (50%)"),
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
