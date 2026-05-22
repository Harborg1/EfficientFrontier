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
  
  // Benchmark / Sammenligning state
  String _selectedTimeframe = 'max';
  // Standard værdi: vi præfikser standard benchmarks med 'bench_'
  String _selectedComparisonId = 'bench_SPY'; 
  final List<String> _benchmarks = ['SPY', 'QQQ', 'DIA', 'IWM'];

  // Statistikker fra backend (Backtest)
  Map<String, dynamic>? _portfolioStats;
  Map<String, dynamic>? _benchmarkStats;
  double? _portfolioCorrelation;
  String? _correlationPeriod;
  String? _backtestError;
  String? _correlationError;
  String? _simulationError;

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
    if (startStr == null || startStr.isEmpty) return "";
    try {
      DateTime startDate = DateTime.parse(startStr);
      int daysToAdd = (value * 1.442).toInt(); 
      DateTime date = startDate.add(Duration(days: daysToAdd));
      
      List<String> months = ["Jan", "Feb", "Mar", "Apr", "Maj", "Jun", "Jul", "Aug", "Sep", "Okt", "Nov", "Dec"];
      return "${months[date.month - 1]} ${date.year.toString().substring(2)}";
    } catch (e) {
      return "";
    }
  }

  _PortfolioPayload _payloadFromPortfolio(Map<String, dynamic> data) {
    final rawWeights = data['weights'];
    if (rawWeights is! Map) {
      throw const FormatException("Saved portfolio is missing weights.");
    }

    final rawTickers = data['tickers'];
    if (rawTickers is! Iterable) {
      throw const FormatException("Saved portfolio is missing tickers.");
    }

    final tickers = <String>[];
    final weights = <String, double>{};

    for (final rawTicker in rawTickers) {
      final ticker = rawTicker.toString();
      if (ticker.isEmpty) {
        throw const FormatException("Saved portfolio contains an empty ticker.");
      }

      final weight = rawWeights[ticker];
      if (weight is! num) {
        throw FormatException("Saved portfolio is missing a numeric weight for $ticker.");
      }

      tickers.add(ticker);
      weights[ticker] = weight.toDouble();
    }

    if (tickers.isEmpty) {
      throw const FormatException("Saved portfolio has no tickers.");
    }

    return _PortfolioPayload(
      tickers: tickers,
      weights: weights,
    );
  }

  Map<String, dynamic> _backtestRequestBody(
    _PortfolioPayload payload,
    String startDate,
    String endDate,
    String benchmark,
  ) {
    return {
      "tickers": payload.tickers,
      "weights": payload.weights,
      "test_start_date": startDate,
      "test_end_date": endDate,
      "benchmark": benchmark,
    };
  }

  Map<String, dynamic> _decodeApiResponse(http.Response response, String action) {
    dynamic decoded;
    try {
      decoded = jsonDecode(response.body);
    } catch (_) {
      decoded = null;
    }

    if (response.statusCode != 200) {
      final detail = decoded is Map ? decoded['detail'] : null;
      final message = detail?.toString() ??
          (response.body.isNotEmpty ? response.body : "No response body");
      throw Exception("$action failed (${response.statusCode}): $message");
    }

    if (decoded is Map<String, dynamic>) return decoded;
    if (decoded is Map) return Map<String, dynamic>.from(decoded);
    throw FormatException("$action returned an unexpected response.");
  }

  String _displayError(Object error) {
    return error
        .toString()
        .replaceFirst("Exception: ", "")
        .replaceFirst("FormatException: ", "");
  }

  // --- API KALD TIL BACKEND (Backtest - Out of Sample) ---
  // Vi sender 'docs' med ind, så vi kan slå den portefølje op, vi vil sammenligne med.
  Future<void> _fetchBacktestData(List<QueryDocumentSnapshot> docs) async {
    if (_selectedPortfolioData == null) return;

    setState(() {
      _isLoading = true;
      _portfolioSpots = [];
      _benchmarkSpots = [];
      _portfolioStats = null;
      _benchmarkStats = null;
      _backtestError = null;
    });

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

    if (startDateObj.isBefore(trainEndDate)) {
      startDateObj = trainEndDate;
    }

    final String finalStartStr = startDateObj.toIso8601String().substring(0, 10);
    final String finalEndStr = today.toIso8601String().substring(0, 10);

    setState(() => _currentVisibleStartDate = finalStartStr);

    final url = Uri.parse('https://efficientfrontier.onrender.com/backtest');

    try {
      final selectedPayload = _payloadFromPortfolio(_selectedPortfolioData!);

      // 1. SCENARIE: INGEN SAMMENLIGNING
      if (_selectedComparisonId == 'none') {
        final response = await http.post(url, headers: {"Content-Type": "application/json"},
          body: jsonEncode(_backtestRequestBody(
            selectedPayload,
            finalStartStr,
            finalEndStr,
            "SPY",
          ))
        ).timeout(const Duration(seconds: 125));

        final data = _decodeApiResponse(response, "Backtest");
        if (!mounted) return;
        setState(() {
          _portfolioSpots = _mapToSpots(data['portfolio']);
          _portfolioStats = data['portfolio_stats'];
          _benchmarkSpots = [];
          _benchmarkStats = null;
        });
      } 
      // 2. SCENARIE: STANDARD BENCHMARK
      else if (_selectedComparisonId.startsWith('bench_')) {
        final ticker = _selectedComparisonId.replaceFirst('bench_', '');
        final response = await http.post(url, headers: {"Content-Type": "application/json"},
          body: jsonEncode(_backtestRequestBody(
            selectedPayload,
            finalStartStr,
            finalEndStr,
            ticker,
          ))
        ).timeout(const Duration(seconds: 125));

        final data = _decodeApiResponse(response, "Backtest");
        if (!mounted) return;
        setState(() {
          _portfolioSpots = _mapToSpots(data['portfolio']);
          _portfolioStats = data['portfolio_stats'];
          _benchmarkSpots = _mapToSpots(data['benchmark']);
          _benchmarkStats = data['benchmark_stats'];
        });
      } 
      // 3. SCENARIE: SAMMENLIGN MED ANDEN PORTEFØLJE
      else {
        // Find den anden porteføljes data
        final compDoc = docs.firstWhere((d) => d.id == _selectedComparisonId);
        final compData = compDoc.data() as Map<String, dynamic>;
        final compPayload = _payloadFromPortfolio(compData);

        // Send 2 API kald afsted samtidigt for at spare tid
        final req1 = http.post(url, headers: {"Content-Type": "application/json"},
          body: jsonEncode(_backtestRequestBody(
            selectedPayload,
            finalStartStr,
            finalEndStr,
            "SPY",
          ))
        );

        final req2 = http.post(url, headers: {"Content-Type": "application/json"},
          body: jsonEncode(_backtestRequestBody(
            compPayload,
            finalStartStr,
            finalEndStr,
            "SPY",
          ))
        );

        final responses = await Future.wait([req1, req2]).timeout(const Duration(seconds: 125));
        final dataMain = _decodeApiResponse(responses[0], "Selected portfolio backtest");
        final dataComp = _decodeApiResponse(responses[1], "Comparison portfolio backtest");

        if (!mounted) return;
        setState(() {
          _portfolioSpots = _mapToSpots(dataMain['portfolio']);
          _portfolioStats = dataMain['portfolio_stats'];
          
          // Hent 'portfolio' dataen fra kald nr 2, og sæt den som vores 'benchmark'!
          _benchmarkSpots = _mapToSpots(dataComp['portfolio']);
          _benchmarkStats = dataComp['portfolio_stats'];
        });
      }
    } catch (e) {
      if (!mounted) return;
      final error = _displayError(e);
      setState(() {
        _backtestError = error;
        _portfolioStats = null;
        _benchmarkStats = null;
        _portfolioSpots = [];
        _benchmarkSpots = [];
      });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _fetchCorrelationData() async {
    if (_selectedPortfolioData == null) return;

    setState(() {
      _isCorrelationLoading = true;
      _portfolioCorrelation = null;
      _correlationPeriod = null;
      _correlationError = null;
    });

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

    if (startDateObj.isBefore(trainEndDate)) startDateObj = trainEndDate;

    final String finalStartStr = startDateObj.toIso8601String().substring(0, 10);
    final String finalEndStr = "${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}";

    final url = Uri.parse('https://efficientfrontier.onrender.com/correlation');

    try {
      final payload = _payloadFromPortfolio(_selectedPortfolioData!);
      final response = await http.post(
        url,
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "tickers": payload.tickers,
          "weights": payload.weights,
          "test_start_date": finalStartStr,
          "test_end_date": finalEndStr,
        }),
      ).timeout(const Duration(seconds: 120));

      final data = _decodeApiResponse(response, "Correlation");
      if (!mounted) return;
      setState(() {
        _portfolioCorrelation = (data['portfolio_correlation'] as num?)?.toDouble();
        _correlationPeriod = "${data['period_start']} - ${data['period_end']}";
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _correlationError = _displayError(e));
    } finally {
      if (mounted) setState(() => _isCorrelationLoading = false);
    }
  }

  Future<void> _fetchSimulationData() async {
    if (_selectedPortfolioData == null) return;
    setState(() {
      _isSimulating = true;
      _simulationError = null;
      _riskMetrics = null;
      _simulationPaths = {};
    });

    final String histStartDate = _selectedPortfolioData!['train_start_date'];
    final DateTime today = DateTime.now();
    final String finalEndStr = "${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}";

    final url = Uri.parse('https://efficientfrontier.onrender.com/simulate');

    try {
      final payload = _payloadFromPortfolio(_selectedPortfolioData!);
      final response = await http.post(
        url,
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "tickers": payload.tickers,
          "weights": payload.weights,
          "hist_start_date": histStartDate, 
          "hist_end_date": finalEndStr,    
          "days_to_sim": 252, 
          "simulations": 1000,
        }),
      ).timeout(const Duration(seconds:90));

      final data = _decodeApiResponse(response, "Simulation");
      final forecast = data['forecast'];
      if (!mounted) return;
      setState(() {
        _riskMetrics = data['risk_metrics'];
        _simulationPaths = {
          'p95': _mapToSpotsList(forecast['p95']),
          'p75': _mapToSpotsList(forecast['p75']),
          'median': _mapToSpotsList(forecast['median']),
          'p25': _mapToSpotsList(forecast['p25']),
          'p5': _mapToSpotsList(forecast['p5']),
        };
      });
    } catch (e) {
      if (!mounted) return;
      final error = _displayError(e);
      setState(() => _simulationError = error);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
    } finally {
      if (mounted) setState(() => _isSimulating = false);
    }
  }

  List<FlSpot> _mapToSpotsList(List<dynamic> values) {
    return values.asMap().entries.map((e) => FlSpot(e.key.toDouble(), (e.value as num).toDouble())).toList();
  }
  
  List<FlSpot> _mapToSpots(List<dynamic> jsonList) {
    return jsonList.map((p) => FlSpot((p['x'] as num).toDouble(), (p['y'] as num).toDouble())).toList();
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
              Tab(text: "Future (Prediction)", icon: Icon(Icons.auto_graph)),
            ],
          ),
        ),
        body: user == null
            ? const Center(child: Text("Login to view performance data"))
            : StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('users')
                    .doc(user.uid)
                    .collection('saved_portfolios')
                    .orderBy('timestamp', descending: true)
                    .snapshots(),
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return Center(child: Text("Error loading saved portfolios: ${snapshot.error}"));
                  }
                  if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
                  final docs = snapshot.data!.docs;
                  if (docs.isEmpty) {
                    return const Center(child: Text("No saved portfolios found."));
                  }
                  final selectedPortfolioValue =
                      docs.any((doc) => doc.id == _selectedPortfolioId) ? _selectedPortfolioId : null;

                  return Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      children: [
                        // --- GLOBAL KONTROL: Valg af portefølje ---
                        DropdownButtonFormField<String>(
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'Select Portfolio',
                            border: OutlineInputBorder(),
                            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          ),
                          value: selectedPortfolioValue,
                          items: docs.map((doc) {
                            final data = doc.data() as Map<String, dynamic>;
                            return DropdownMenuItem(
                              value: doc.id,
                              child: Text(
                                "${data['type']} (${data['tickers'].length} stocks) - Trained: ${data['train_start_date'] ?? 'N/A'}-${data['train_end_date'] ?? 'N/A'}",
                                style: const TextStyle(fontSize: 12),
                              ),
                            );
                          }).toList(),
                          onChanged: (id) {
                            setState(() {
                              _selectedPortfolioId = id;
                              _selectedPortfolioData = docs.firstWhere((d) => d.id == id).data() as Map<String, dynamic>;
                              
                              if (_selectedComparisonId == id) {
                                _selectedComparisonId = 'bench_SPY';
                              }
                            });
                            _fetchBacktestData(docs); 
                            _fetchCorrelationData();
                            _fetchSimulationData();
                          },
                        ),

                        const SizedBox(height: 24),

                        // Korrelationskortet er nu FJERNET herfra!

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
                                  
                                  // DROPDOWNS SIDE OM SIDE
                                  Row(
                                    children: [
                                      // SAMMENLIGNINGS DROPDOWN
                                      Expanded(
                                        child: DropdownButtonFormField<String>(
                                          isExpanded: true,
                                          decoration: const InputDecoration(
                                            labelText: 'Compare with',
                                            border: OutlineInputBorder(),
                                            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                          ),
                                          value: _selectedComparisonId,
                                          items: [
                                            const DropdownMenuItem(value: 'none', child: Text('None', style: TextStyle(fontSize: 12))),
                                            ..._benchmarks.map((ticker) => DropdownMenuItem(
                                              value: 'bench_$ticker', 
                                              child: Text('Benchmark: $ticker', style: const TextStyle(fontSize: 12))
                                            )),
                                            ...docs.where((doc) => doc.id != _selectedPortfolioId).map((doc) {
                                              final data = doc.data() as Map<String, dynamic>;
                                              return DropdownMenuItem(
                                                value: doc.id,
                                                child: Text('Portfolio: ${data['type']} (${data['tickers'].length} stocks)', style: const TextStyle(fontSize: 12)),
                                              );
                                            }),
                                          ],
                                          onChanged: (val) {
                                            if (val != null) {
                                              setState(() => _selectedComparisonId = val);
                                              _fetchBacktestData(docs);
                                            }
                                          },
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      
                                      // Test-længde valg
                                      Expanded(
                                        child: DropdownButtonFormField<String>(
                                          decoration: const InputDecoration(
                                            labelText: 'Test-length',
                                            border: OutlineInputBorder(),
                                            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                          ),
                                          value: _selectedTimeframe,
                                          items: const [
                                            DropdownMenuItem(value: '1mo', child: Text('1 Month')),
                                            DropdownMenuItem(value: '6mo', child: Text('6 Months')),
                                            DropdownMenuItem(value: '1y', child: Text('1 Year')),
                                            DropdownMenuItem(value: 'max', child: Text('Max')),
                                          ],
                                          onChanged: (val) {
                                            if (val != null) {
                                              setState(() => _selectedTimeframe = val);
                                              _fetchBacktestData(docs);
                                              _fetchCorrelationData();
                                              _fetchSimulationData();
                                            }
                                          },
                                        ),
                                      ),
                                    ],
                                  ),
                                  
                                  const SizedBox(height: 16),
                                  
                                  // ---> NY PLACERING AF KORRELATIONSKORTET <---
                                  _buildCorrelationCard(theme),
                                  
                                  const SizedBox(height: 16),
                                  
                                  if (_portfolioStats != null && !_isLoading) _buildStatsTable(theme),
                                  
                                  const SizedBox(height: 16),
                                  
                                  Expanded(
                                    child: _isLoading
                                        ? const Center(child: CircularProgressIndicator())
                                        : _backtestError != null
                                            ? Center(child: Text(_backtestError!, textAlign: TextAlign.center))
                                            : _portfolioSpots.isEmpty
                                                ? const Center(child: Text("No backtest data available for this period"))
                                                : _buildSlightlyWiderChart(LineChart(_buildChartData(theme))),
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
                                        : _simulationError != null
                                            ? Center(child: Text(_simulationError!, textAlign: TextAlign.center))
                                            : _simulationPaths.isEmpty
                                                ? const Center(child: Text("Select a portfolio to view simulation results"))
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
                  );
                },
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
            _statItem("Sharpe", _portfolioStats?['sharpe'],_benchmarkStats?['sharpe']),
            _statItem("Sortino", _portfolioStats?['sortino'],_benchmarkStats?['sortino']),
            _statItem("Volatility", "${_portfolioStats?['volatility']}%", _benchmarkStats != null ? "${_benchmarkStats?['volatility']}%" : null),
            _statItem("Return", "${_portfolioStats?['perf']}%", _benchmarkStats != null ? "${_benchmarkStats?['perf']}%" : null),
          ],
        ),
      ),
    );
  }

  Widget _statItem(String label, dynamic portVal, dynamic benchVal) {
    bool hasComparison = _selectedComparisonId != 'none';
    String prefix = _selectedComparisonId.startsWith('bench_') ? "B:" : "Sml:"; // Sml = Sammenligning

    return Column(
      children: [
        Text(label, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
        const SizedBox(height: 4),
        Text("P: $portVal", style: TextStyle(color: Theme.of(context).colorScheme.primary, fontSize: 11)),
        if (hasComparison && benchVal != null)
          Text("$prefix $benchVal", style: const TextStyle(color: Colors.orange, fontSize: 11)),
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
                  const Text("Portfolio Correlation", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                  const SizedBox(height: 4),
                  Text(
                    _isCorrelationLoading
                        ? "Calculating correlation..."
                        : _correlationError != null
                            ? _correlationError!
                            : _portfolioCorrelation == null
                                ? "No correlation available"
                                : _portfolioCorrelation!.toStringAsFixed(3),
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                  if (_correlationPeriod != null) ...[
                    const SizedBox(height: 4),
                    Text(_correlationPeriod!, style: TextStyle(fontSize: 11, color: Colors.blueGrey.shade600)),
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
    double maxXValue = _portfolioSpots.isNotEmpty ? _portfolioSpots.last.x : 0;

    return LineChartData(
      maxX: maxXValue > 0 ? maxXValue * 1.1 : null,
      clipData: const FlClipData.all(),
      
      lineTouchData: LineTouchData(
        touchTooltipData: LineTouchTooltipData(
          getTooltipColor: (LineBarSpot touchedSpot) => Colors.blueGrey.withOpacity(0.8),
          tooltipRoundedRadius: 8,
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
      
      gridData: FlGridData(
        show: true, 
        drawVerticalLine: true, 
        getDrawingHorizontalLine: (v) => FlLine(color: Colors.grey.withOpacity(0.05), strokeWidth: 1),
        getDrawingVerticalLine: (v) => FlLine(color: Colors.grey.withOpacity(0.05), strokeWidth: 1),
      ),

      titlesData: FlTitlesData(
        rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false, reservedSize: 0)),
        bottomTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 32,
            interval: 64, 
            getTitlesWidget: (value, meta) {
              if (value == meta.min || value == meta.max) return const SizedBox.shrink();
              return SideTitleWidget(
                meta: meta,
                space: 8,
                child: Text(
                  _formatDateLabel(value, _currentVisibleStartDate), 
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.w500, color: Colors.blueGrey.shade600),
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
        // Vi tilføjer KUN den orange linje, hvis brugeren har valgt en benchmark/portefølje at sammenligne med
        if (_benchmarkSpots.isNotEmpty)
          LineChartBarData(
            spots: _benchmarkSpots,
            isCurved: true,
            color: Colors.orange.withOpacity(0.7), 
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
    double maxXValue = 0;
    if (_simulationPaths.containsKey('median') && _simulationPaths['median']!.isNotEmpty) {
      maxXValue = _simulationPaths['median']!.last.x;
    }

    final String todayStr = DateTime.now().toIso8601String().substring(0, 10);

    return LineChartData(
      maxX: maxXValue > 0 ? maxXValue * 1.1 : null,
      clipData: const FlClipData.all(),

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

      gridData: FlGridData(
        show: true,
        drawVerticalLine: true,
        getDrawingHorizontalLine: (v) => FlLine(color: Colors.grey.withOpacity(0.05), strokeWidth: 1),
        getDrawingVerticalLine: (v) => FlLine(color: Colors.grey.withOpacity(0.05), strokeWidth: 1),
      ),

      titlesData: FlTitlesData(
        rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false, reservedSize: 0)),
        bottomTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 32,
            interval: 64, 
            getTitlesWidget: (value, meta) {
              if (value == meta.min || value == meta.max) return const SizedBox.shrink();
              return SideTitleWidget(
                meta: meta,
                space: 8,
                child: Text(
                  _formatDateLabel(value, todayStr),
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.w500, color: Colors.blueGrey.shade600),
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
            _simStatItem("Risk of loss (1 year)", "${_riskMetrics!['prob_of_loss_percent']}%", Colors.redAccent),
            _simStatItem("Expected Value (1 year)", "${_riskMetrics!['expected_final_value']}", Colors.green),
            _simStatItem("CVaR (Worst 5%)", "${_riskMetrics!['worst_case_cvar_5pct']}", Colors.deepOrange),
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

  LineChartBarData _simLayer({required List<FlSpot> spots, required Color color, double width = 0, bool fill = true}) {
    return LineChartBarData(
      spots: spots,
      isCurved: true,
      color: color,
      barWidth: width,
      dotData: const FlDotData(show: false),
      belowBarData: BarAreaData(show: fill, color: color),
    );
  }

  Widget _buildSimulationChart(ThemeData theme) {
    if (_simulationPaths.isEmpty) return const Center(child: Text("No simulation data available"));

    return _buildSlightlyWiderChart(
      LineChart(_buildSimulationChartData(theme)),
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
          _legendCircle(theme.colorScheme.primary.withOpacity(0.6), "Probable (50%)"),
          const SizedBox(width: 15),
          _legendCircle(theme.colorScheme.primary.withOpacity(0.1), "Extreme (90%)"),
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

class _PortfolioPayload {
  const _PortfolioPayload({
    required this.tickers,
    required this.weights,
  });

  final List<String> tickers;
  final Map<String, double> weights;
}
