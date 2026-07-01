import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:math'; // Added for min/max calculations
import 'package:fl_chart/fl_chart.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:backtesting/screens/welcome_screen.dart';

class FrontierScreen extends StatefulWidget {
  const FrontierScreen({super.key});

  @override
  State<FrontierScreen> createState() => _FrontierScreenState();
}

class _FrontierScreenState extends State<FrontierScreen> {
  // --- STATE VARIABLES ---
  final TextEditingController _tickerController = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  final List<String> _tickerUniverse = [
    "AAPL", "MSFT", "GOOGL", "AMZN", "META", "TSLA", "NVDA", "BRK-B", "JPM", "V", 
    "JNJ", "WMT", "PG", "MA", "UNH", "HD", "DIS", "BAC", "VZ", "KO", "PFE", 
    "INTC", "CMCSA", "NFLX", "ADBE", "T", "ABT", "PEP", "XOM", "CSCO"
  ];

  List<String> selectedTickers = ['AAPL', 'MSFT', 'GOOGL','TSLA', 'XOM','V' , 'JNJ', 'AMZN', 'WMT','ADBE'];
  double _selectedMaxWeight = 0.30;
  int _selectedPortfolios = 20000;
  String _selectedTimeframe = '5 YR';
  bool _useLedoitWolf = false;
  double _selectedReturnShrinkage = 0.0;
  
  final List<double> _weightOptions = [0.10, 0.20, 0.30, 0.40, 0.50, 1.00];
  final List<int> _portfolioOptions = [20000, 40000, 70000, 100000];
  final List<_RebalanceChoice> _rebalanceChoices = const [
    _RebalanceChoice(code: 'skip', label: 'Skip (never)', months: null),
    _RebalanceChoice(code: '3mo', label: 'Every 3 months', months: 3),
    _RebalanceChoice(code: '6mo', label: 'Every 6 months', months: 6),
    _RebalanceChoice(code: '1y', label: 'Every 1 year', months: 12),
    _RebalanceChoice(code: 'custom', label: 'Custom period', months: null),
  ];

  String _selectedRebalanceCode = 'skip';
  int _customRebalanceMonths = 9;
  final List<String> _timeframeOptions = ['1 YR', '3 YR', '5 YR', '10 YR'];
  final List<_ReturnShrinkageChoice> _returnShrinkageChoices = const [
    _ReturnShrinkageChoice(value: 0.0, label: 'None'),
    _ReturnShrinkageChoice(value: 0.25, label: 'Light'),
    _ReturnShrinkageChoice(value: 0.5, label: 'Medium'),
    _ReturnShrinkageChoice(value: 0.75, label: 'Strong'),
  ];
  
  List<ScatterSpot> scatterSpots = [];
  Map<String, dynamic>? maxSharpe;
  Map<String, dynamic>? minVol;
  Map<String, dynamic>? maxSortino;
  List<Map<String, dynamic>> rebalanceRuns = [];
  Map<String, dynamic>? rebalanceSummary;
  String? rebalanceError;

  bool isLoading = false;
  bool showSimulation = false;

  // --- NYE VARIABLER TIL MANUEL PORTEFØLJE ---
  Map<String, double> customWeights = {};
  DateTime customStartDate = DateTime.now().subtract(const Duration(days: 365 * 5));
  DateTime customEndDate = DateTime.now().subtract(const Duration(days: 365));
  bool isCustomLoading = false;
  
  bool _isCustomPortfolioExpanded = false; 

  @override
  void initState() {
    super.initState();
    _syncCustomWeights(); // Sikrer at standardaktierne har en vægt fra start
  }

  @override
  void dispose() {
    _tickerController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  // --- HJÆLPER: Synkroniser manuelle vægte med valgte aktier ---
  void _syncCustomWeights() {
    if (selectedTickers.isEmpty) {
      customWeights.clear();
      return;
    }
    double defaultWeight = 100.0 / selectedTickers.length;
    for (var ticker in selectedTickers) {
      customWeights.putIfAbsent(ticker, () => defaultWeight);
    }
    // Fjern tickers fra customWeights, som ikke længere er valgt
    customWeights.removeWhere((key, value) => !selectedTickers.contains(key));
  }

  List<double> get _availableWeightOptions {
    if (selectedTickers.isEmpty) return _weightOptions;
    if (selectedTickers.length == 1) return const [1.00];

    final minimumUsefulWeight = 1.0 / selectedTickers.length;
    return _weightOptions.where((weight) => weight > minimumUsefulWeight).toList();
  }

  void _ensureSelectedMaxWeightIsValid() {
    final availableOptions = _availableWeightOptions;
    if (availableOptions.isEmpty) return;
    if (!availableOptions.contains(_selectedMaxWeight)) {
      _selectedMaxWeight = availableOptions.first;
    }
  }

  Map<String, double> _weightsFromOptimizedPortfolio(Map<String, dynamic> portfolio) {
    final rawWeights = portfolio['weights'] as Map;
    return rawWeights.map(
      (ticker, weight) => MapEntry(ticker.toString(), (weight as num).toDouble()),
    );
  }

  String _formatDate(DateTime date) {
    return "${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}";
  }

  int _daysInMonth(int year, int month) {
    return DateTime(year, month + 1, 0).day;
  }

  DateTime _addMonths(DateTime date, int months) {
    final monthIndex = date.month - 1 + months;
    final year = date.year + (monthIndex ~/ 12);
    final month = (monthIndex % 12) + 1;
    final day = min(date.day, _daysInMonth(year, month));
    return DateTime(year, month, day);
  }

  DateTime _trainingStartFor(DateTime endDate, String timeframe) {
    switch (timeframe) {
      case '1 YR':
        return DateTime(endDate.year - 1, endDate.month, endDate.day);
      case '3 YR':
        return DateTime(endDate.year - 3, endDate.month, endDate.day);
      case '10 YR':
        return DateTime(endDate.year - 10, endDate.month, endDate.day);
      case '5 YR':
      default:
        return DateTime(endDate.year - 5, endDate.month, endDate.day);
    }
  }

  int _lookbackYearsForTimeframe(String timeframe) {
    if (timeframe.startsWith('1')) return 1;
    if (timeframe.startsWith('3')) return 3;
    if (timeframe.startsWith('10')) return 10;
    return 5;
  }
  
  int? get _selectedRebalanceMonths {
    if (_selectedRebalanceCode == 'custom') {
      return _customRebalanceMonths > 0 ? _customRebalanceMonths : null;
    }

    final choice = _rebalanceChoices.firstWhere(
      (option) => option.code == _selectedRebalanceCode,
      orElse: () => _rebalanceChoices.first,
    );
    return choice.months;
  }

  String get _selectedRebalanceLabel {
    if (_selectedRebalanceCode == 'custom') {
      return "Every $_customRebalanceMonths months";
    }

    final choice = _rebalanceChoices.firstWhere(
      (option) => option.code == _selectedRebalanceCode,
      orElse: () => _rebalanceChoices.first,
    );
    return choice.label;
  }

  Future<Map<String, dynamic>> _requestOptimization({
    required List<String> tickers,
    required double maxWeight,
    required DateTime startDate,
    required DateTime endDate,
    required int numPortfolios,
    required bool useLedoitWolf,
    required double returnShrinkage,
  }) async {
    final url = Uri.parse(
      'https://efficientfrontier.onrender.com/optimize'
      '?tickers=${tickers.join(',')}'
      '&max_weight=$maxWeight'
      '&start_date=${_formatDate(startDate)}'
      '&end_date=${_formatDate(endDate)}'
      '&num_portfolios=$numPortfolios'
      '&use_ledoit_wolf=$useLedoitWolf'
      '&return_shrinkage=$returnShrinkage'
      '&t=${DateTime.now().millisecondsSinceEpoch}'
    );

    final response = await http.get(url).timeout(const Duration(seconds: 2000));
    if (response.statusCode != 200) {
      throw Exception(
        response.body.isNotEmpty
            ? response.body
            : "Optimization failed with status ${response.statusCode}.",
      );
    }

    final decoded = json.decode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException("Optimization returned an unexpected response.");
    }
    if (decoded['error'] != null) {
      throw Exception(decoded['error']);
    }

    return decoded;
  }

  Future<Map<String, dynamic>> _requestRollingBacktest({
    required List<String> tickers,
    required double maxWeight,
    required DateTime backtestStartDate,
    required DateTime backtestEndDate,
    required int lookbackYears,
    required int rebalanceMonths,
    required int numPortfolios,
    required bool useLedoitWolf,
    required double returnShrinkage,
  }) async {
    final response = await http.post(
      Uri.parse('https://efficientfrontier.onrender.com/rolling-backtest'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({
        "tickers": tickers,
        "max_weight": maxWeight,
        "backtest_start_date": _formatDate(backtestStartDate),
        "backtest_end_date": _formatDate(backtestEndDate),
        "lookback_years": lookbackYears,
        "rebalance_months": rebalanceMonths,
        "num_portfolios": numPortfolios,
        "use_ledoit_wolf": useLedoitWolf,
        "return_shrinkage": returnShrinkage,
      }),
    ).timeout(const Duration(seconds: 2000));

    final decoded = json.decode(response.body);
    if (response.statusCode != 200) {
      if (decoded is Map<String, dynamic> && decoded['detail'] != null) {
        throw Exception(decoded['detail']);
      }
      throw Exception(
        response.body.isNotEmpty
            ? response.body
            : "Rolling backtest failed with status ${response.statusCode}.",
      );
    }

    if (decoded is! Map<String, dynamic>) {
      throw const FormatException("Rolling backtest returned an unexpected response.");
    }

    return decoded;
  }

  Future<Map<String, double>> _requestPortfolioStats({
    required List<String> tickers,
    required Map<String, double> weights,
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    final response = await http.post(
      Uri.parse('https://efficientfrontier.onrender.com/portfolio-stats'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({
        "tickers": tickers,
        "weights": weights,
        "start_date": _formatDate(startDate),
        "end_date": _formatDate(endDate),
      }),
    ).timeout(const Duration(seconds: 30));

    if (response.statusCode != 200) {
      throw Exception(
        response.body.isNotEmpty
            ? response.body
            : "Portfolio stats failed with status ${response.statusCode}.",
      );
    }

    final decoded = json.decode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException("Portfolio stats returned an unexpected response.");
    }

    final annualReturn =
        (decoded['annualized_return_pct'] as num).toDouble() / 100;
    final annualVolatility =
        (decoded['annualized_volatility_pct'] as num).toDouble() / 100;
    final sortino = (decoded['sortino_ratio'] as num?)?.toDouble() ?? 0.0;

    return {
      'return': annualReturn,
      'volatility': annualVolatility,
      'sortino': sortino,
      'sharpe': annualVolatility == 0 ? 0.0 : annualReturn / annualVolatility,
    };
  }

  double _scoreForObjective(
    String portfolioKey,
    Map<String, dynamic>? optimizedPortfolio,
    Map<String, double>? stats,
  ) {
    if (optimizedPortfolio != null) {
      final annualReturn = (optimizedPortfolio['y'] as num?)?.toDouble() ?? 0.0;
      final annualVolatility = (optimizedPortfolio['x'] as num?)?.toDouble() ?? 0.0;

      switch (portfolioKey) {
        case 'min_vol':
          return -annualVolatility;
        case 'max_sortino':
          return (optimizedPortfolio['sortino'] as num?)?.toDouble() ?? 0.0;
        case 'max_sharpe':
        default:
          return (optimizedPortfolio['sharpe'] as num?)?.toDouble() ??
              (annualVolatility == 0 ? 0.0 : annualReturn / annualVolatility);
      }
    }

    if (stats == null) return double.negativeInfinity;
    switch (portfolioKey) {
      case 'min_vol':
        return -(stats['volatility'] ?? double.infinity);
      case 'max_sortino':
        return stats['sortino'] ?? 0.0;
      case 'max_sharpe':
      default:
        return stats['sharpe'] ?? 0.0;
    }
  }

  Future<Map<String, dynamic>> _walkForwardPortfolioForObjective({
    required String portfolioKey,
    required Map<String, dynamic> optimizedPortfolio,
    required Map<String, double>? currentWeights,
    required DateTime trainingStart,
    required DateTime rebalanceDate,
    required DateTime applicationEnd,
  }) async {
    final candidateWeights = _weightsFromOptimizedPortfolio(optimizedPortfolio);
    final currentTrainingStats = currentWeights == null
        ? null
        : await _requestPortfolioStats(
            tickers: selectedTickers,
            weights: currentWeights,
            startDate: trainingStart,
            endDate: rebalanceDate,
          );

    final candidateScore = _scoreForObjective(
      portfolioKey,
      optimizedPortfolio,
      null,
    );
    final currentScore = _scoreForObjective(
      portfolioKey,
      null,
      currentTrainingStats,
    );
    final shouldRebalance =
        currentWeights == null || candidateScore > currentScore + 0.0001;
    final selectedWeights = shouldRebalance ? candidateWeights : currentWeights!;

    final applicationStats = await _requestPortfolioStats(
      tickers: selectedTickers,
      weights: selectedWeights,
      startDate: rebalanceDate,
      endDate: applicationEnd,
    );

    return {
      'x': applicationStats['volatility'],
      'y': applicationStats['return'],
      'sortino': applicationStats['sortino'],
      'sharpe': applicationStats['sharpe'],
      'weights': selectedWeights,
      'rebalanced': shouldRebalance,
      'candidate_score': candidateScore,
      'previous_score': currentWeights == null ? null : currentScore,
      'training_return': optimizedPortfolio['y'],
      'training_volatility': optimizedPortfolio['x'],
    };
  }

  Future<List<Map<String, dynamic>>> _calculateRollingRebalances(
    DateTime startDate,
    DateTime endDate,
  ) async {
    final intervalMonths = _selectedRebalanceMonths;
    if (intervalMonths == null) return [];

    final runs = <Map<String, dynamic>>[];
    final currentWeightsByObjective = <String, Map<String, double>?>{
      'max_sharpe': null,
      'min_vol': null,
      'max_sortino': null,
    };
    var trainingStart = startDate;
    var rebalanceDate = _addMonths(trainingStart, intervalMonths);
    var windowNumber = 1;

    while (rebalanceDate.isBefore(endDate)) {
      final rawApplicationEnd = _addMonths(rebalanceDate, intervalMonths);
      final applicationEnd =
          rawApplicationEnd.isAfter(endDate) ? endDate : rawApplicationEnd;

      if (rebalanceDate.difference(trainingStart).inDays < 30 ||
          applicationEnd.difference(rebalanceDate).inDays < 30) {
        break;
      }

      final data = await _requestOptimization(
        tickers: selectedTickers,
        maxWeight: _selectedMaxWeight,
        startDate: trainingStart,
        endDate: rebalanceDate,
        numPortfolios: _selectedPortfolios,
      );

      final maxSharpeRun = await _walkForwardPortfolioForObjective(
        portfolioKey: 'max_sharpe',
        optimizedPortfolio: Map<String, dynamic>.from(data['max_sharpe'] as Map),
        currentWeights: currentWeightsByObjective['max_sharpe'],
        trainingStart: trainingStart,
        rebalanceDate: rebalanceDate,
        applicationEnd: applicationEnd,
      );
      final minVolRun = await _walkForwardPortfolioForObjective(
        portfolioKey: 'min_vol',
        optimizedPortfolio: Map<String, dynamic>.from(data['min_vol'] as Map),
        currentWeights: currentWeightsByObjective['min_vol'],
        trainingStart: trainingStart,
        rebalanceDate: rebalanceDate,
        applicationEnd: applicationEnd,
      );
      final maxSortinoRun = await _walkForwardPortfolioForObjective(
        portfolioKey: 'max_sortino',
        optimizedPortfolio:
            Map<String, dynamic>.from(data['max_sortino'] as Map),
        currentWeights: currentWeightsByObjective['max_sortino'],
        trainingStart: trainingStart,
        rebalanceDate: rebalanceDate,
        applicationEnd: applicationEnd,
      );

      if (maxSharpeRun['rebalanced'] == true) {
        currentWeightsByObjective['max_sharpe'] =
            Map<String, double>.from(maxSharpeRun['weights'] as Map);
      }
      if (minVolRun['rebalanced'] == true) {
        currentWeightsByObjective['min_vol'] =
            Map<String, double>.from(minVolRun['weights'] as Map);
      }
      if (maxSortinoRun['rebalanced'] == true) {
        currentWeightsByObjective['max_sortino'] =
            Map<String, double>.from(maxSortinoRun['weights'] as Map);
      }

      runs.add({
        'number': windowNumber,
        'training_start_date': _formatDate(trainingStart),
        'training_end_date': _formatDate(rebalanceDate),
        'rebalance_date': _formatDate(rebalanceDate),
        'start_date': _formatDate(rebalanceDate),
        'end_date': _formatDate(applicationEnd),
        'max_sharpe': maxSharpeRun,
        'min_vol': minVolRun,
        'max_sortino': maxSortinoRun,
      });

      if (!applicationEnd.isAfter(rebalanceDate)) break;
      trainingStart = rebalanceDate;
      rebalanceDate = applicationEnd;
      windowNumber += 1;
    }

    return runs;
  }

  // --- API LOGIC (Optimering) ---
  Future<void> calculateFrontier() async {
    if (selectedTickers.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Tilføj venligst mindst én ticker.")),
      );
      return;
    }
    if (selectedTickers.length * _selectedMaxWeight < 1.0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Mathematical Error: ${selectedTickers.length} aktier med max vægt ${_selectedMaxWeight * 100}% kan ikke give 100%. Tilføj flere aktier eller øg max vægt.")),
      );
      return;
    }

    setState(() {
      _ensureSelectedMaxWeightIsValid();
      isLoading = true;
      showSimulation = true;
      rebalanceRuns = [];
      rebalanceSummary = null;
      rebalanceError = null;
    });

    final today = DateTime.now();
    final endDate = DateTime(today.year - 1, today.month, today.day); 
    DateTime startDate;
    switch (_selectedTimeframe) {
      case '1 YR': startDate = DateTime(endDate.year - 1, endDate.month, endDate.day); break;
      case '3 YR': startDate = DateTime(endDate.year - 3, endDate.month, endDate.day); break;
      case '10 YR': startDate = DateTime(endDate.year - 10, endDate.month, endDate.day); break;
      case '5 YR':
      default: startDate = DateTime(endDate.year - 5, endDate.month, endDate.day); break;
    }

    final lookbackYears = _lookbackYearsForTimeframe(_selectedTimeframe);
    startDate = DateTime(endDate.year - lookbackYears, endDate.month, endDate.day);

    try {
      final data = await _requestOptimization(
        tickers: selectedTickers,
        maxWeight: _selectedMaxWeight,
        startDate: startDate,
        endDate: endDate,
        numPortfolios: _selectedPortfolios,
        useLedoitWolf: _useLedoitWolf,
        returnShrinkage: _selectedReturnShrinkage,
      );
      List<Map<String, dynamic>> rollingRuns = [];
      Map<String, dynamic>? rollingSummary;
      String? rollingError;

      if (_selectedRebalanceMonths != null) {
        try {
          final rollingData = await _requestRollingBacktest(
            tickers: selectedTickers,
            maxWeight: _selectedMaxWeight,
            backtestStartDate: startDate,
            backtestEndDate: endDate,
            lookbackYears: lookbackYears,
            rebalanceMonths: _selectedRebalanceMonths!,
            numPortfolios: _selectedPortfolios,
            useLedoitWolf: _useLedoitWolf,
            returnShrinkage: _selectedReturnShrinkage,
          );
          rollingRuns = (rollingData['runs'] as List)
              .map((run) => Map<String, dynamic>.from(run as Map))
              .toList();
          rollingSummary = rollingData['summary'] is Map
              ? Map<String, dynamic>.from(rollingData['summary'] as Map)
              : null;
        } catch (e) {
          rollingError = e
              .toString()
              .replaceFirst("Exception: ", "")
              .replaceFirst("FormatException: ", "");
        }
      }
        
        List<ScatterSpot> rawSpots = (data['scatter_points'] as List).map((p) {
          return ScatterSpot((p['x'] as num).toDouble(), (p['y'] as num).toDouble());
        }).toList();

        setState(() {
          scatterSpots = rawSpots.map((s) => ScatterSpot(
            s.x, s.y,
            dotPainter: FlDotCirclePainter(radius: 1, color: Colors.blueGrey.withOpacity(0.3))
          )).toList();
          
          maxSharpe = data['max_sharpe'];
          minVol = data['min_vol'];
          maxSortino = data['max_sortino'];
          rebalanceRuns = rollingRuns;
          rebalanceSummary = rollingSummary;
          rebalanceError = rollingError;
          isLoading = false;
        });

        if (rollingError != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("Rebalance error: $rollingError")),
          );
        }
    } catch (e) {
      setState(() {
        isLoading = false;
        showSimulation = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
    }
  }

  // --- DATO VÆLGER TIL MANUEL PORTEFØLJE ---
  Future<void> _selectCustomDate(BuildContext context, bool isStart) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: isStart ? customStartDate : customEndDate,
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
    );
    if (picked != null) {
      setState(() {
        if (isStart) customStartDate = picked;
        else customEndDate = picked;
      });
    }
  }
  
  // --- GEM LOGIK (Manuel Portefølje) ---
  Future<void> saveCustomPortfolio() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Log venligst ind for at gemme porteføljer.")));
      return;
    }

    if (selectedTickers.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Vælg venligst mindst én aktie.")));
      return;
    }

    setState(() => isCustomLoading = true);

    try {
      final userPortfoliosRef = FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('saved_portfolios');

      final startStr = "${customStartDate.year}-${customStartDate.month.toString().padLeft(2, '0')}-${customStartDate.day.toString().padLeft(2, '0')}";
      final endStr = "${customEndDate.year}-${customEndDate.month.toString().padLeft(2, '0')}-${customEndDate.day.toString().padLeft(2, '0')}";

      // Normaliser vægtene så de summerer til 1.0 (100%)
      Map<String, double> normalizedWeights = {};
      double totalWeight = customWeights.values.fold(0, (sum, item) => sum + item);
      
      for (var ticker in selectedTickers) {
        normalizedWeights[ticker] = totalWeight > 0 ? (customWeights[ticker] ?? 0) / totalWeight : 0;
      }

      // 1. Hent afkast og volatilitet lydløst fra backenden
      double annualReturn = 0.0;
      double annualVolatility = 0.0;
      double sortinoRatio = 0.0;

      final url = Uri.parse('https://efficientfrontier.onrender.com/portfolio-stats');
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          "tickers": selectedTickers,
          "weights": normalizedWeights,
          "start_date": startStr,
          "end_date": endStr,
        }),
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final stats = json.decode(response.body);
        // Backend returnerer f.eks. 15.5 for 15.5%. Vi deler med 100 for at gemme som decimal (0.155)
        annualReturn = (stats['annualized_return_pct'] as num).toDouble() / 100;
        annualVolatility = (stats['annualized_volatility_pct'] as num).toDouble() / 100;
        sortinoRatio = (stats['sortino_ratio'] as num?)?.toDouble() ?? 0.0;
      } else {
        print("Kunne ikke hente stats fra backend. Gemmer portefølje med 0.0");
      }

      // 2. Gem porteføljen i Firestore MED de rigtige tal
      await userPortfoliosRef.add({
        'type': 'Manuel',
        'tickers': List.from(selectedTickers),
        'return': annualReturn, 
        'volatility': annualVolatility, 
        'sortino': sortinoRatio,
        'weights': normalizedWeights,
        'train_start_date': startStr, 
        'train_end_date': endStr,     
        'timestamp': FieldValue.serverTimestamp(),
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Manual portfolio saved with return and volatility!"))
      );

      // Luk accordion menuen for et renere UI
      setState(() {
        _isCustomPortfolioExpanded = false;
      });

    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error saving portfolio: $e")));
    } finally {
      setState(() => isCustomLoading = false);
    }
  }

  // --- FIRESTORE PERSISTENCE (Optimerede) ---
  Future<void> showSavePortfolioDialog() async {
    if (maxSharpe == null || minVol == null || maxSortino == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Run the optimizer before saving portfolios.")),
      );
      return;
    }

    final selectedTypes = <String>{'Max Sharpe', 'Min Risk', 'Max Sortino'};
    if (rebalanceRuns.isNotEmpty) {
      selectedTypes.addAll({
        'Rebalanced Max Sharpe',
        'Rebalanced Min Risk',
        'Rebalanced Max Sortino',
      });
    }

    final typesToSave = await showDialog<Set<String>>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            void toggleType(String type, bool? isSelected) {
              setDialogState(() {
                if (isSelected == true) {
                  selectedTypes.add(type);
                } else {
                  selectedTypes.remove(type);
                }
              });
            }

            return AlertDialog(
              title: const Text("Save portfolios"),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CheckboxListTile(
                      value: selectedTypes.contains('Max Sharpe'),
                      onChanged: (value) => toggleType('Max Sharpe', value),
                      title: const Text("Max Sharpe"),
                      controlAffinity: ListTileControlAffinity.leading,
                    ),
                    CheckboxListTile(
                      value: selectedTypes.contains('Min Risk'),
                      onChanged: (value) => toggleType('Min Risk', value),
                      title: const Text("Min Volatility"),
                      controlAffinity: ListTileControlAffinity.leading,
                    ),
                    CheckboxListTile(
                      value: selectedTypes.contains('Max Sortino'),
                      onChanged: (value) => toggleType('Max Sortino', value),
                      title: const Text("Max Sortino"),
                      controlAffinity: ListTileControlAffinity.leading,
                    ),
                    if (rebalanceRuns.isNotEmpty) ...[
                      const Divider(),
                      CheckboxListTile(
                        value: selectedTypes.contains('Rebalanced Max Sharpe'),
                        onChanged: (value) => toggleType('Rebalanced Max Sharpe', value),
                        title: const Text("SHA' Rebalanced Max Sharpe"),
                        controlAffinity: ListTileControlAffinity.leading,
                      ),
                      CheckboxListTile(
                        value: selectedTypes.contains('Rebalanced Min Risk'),
                        onChanged: (value) => toggleType('Rebalanced Min Risk', value),
                        title: const Text("VAR' Rebalanced Min Volatility"),
                        controlAffinity: ListTileControlAffinity.leading,
                      ),
                      CheckboxListTile(
                        value: selectedTypes.contains('Rebalanced Max Sortino'),
                        onChanged: (value) => toggleType('Rebalanced Max Sortino', value),
                        title: const Text("SOR' Rebalanced Max Sortino"),
                        controlAffinity: ListTileControlAffinity.leading,
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text("Cancel"),
                ),
                ElevatedButton(
                  onPressed: selectedTypes.isEmpty
                      ? null
                      : () => Navigator.of(context).pop(Set<String>.from(selectedTypes)),
                  child: const Text("Save"),
                ),
              ],
            );
          },
        );
      },
    );

    if (typesToSave == null || typesToSave.isEmpty) return;
    await saveSelectedPortfolios(typesToSave);
  }

  Future<void> saveSelectedPortfolios(Set<String> typesToSave) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Please log in to save portfolios.")));
      return;
    }

    if (maxSharpe != null && minVol != null && maxSortino != null) {
      final batch = FirebaseFirestore.instance.batch();
      final userPortfoliosRef = FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('saved_portfolios');

      final today = DateTime.now();
      final endDate = DateTime(today.year - 1, today.month, today.day); 
      DateTime startDate;
      switch (_selectedTimeframe) {
        case '1 YR': startDate = DateTime(endDate.year - 1, endDate.month, endDate.day); break;
        case '3 YR': startDate = DateTime(endDate.year - 3, endDate.month, endDate.day); break;
        case '10 YR': startDate = DateTime(endDate.year - 10, endDate.month, endDate.day); break;
        case '5 YR':
        default: startDate = DateTime(endDate.year - 5, endDate.month, endDate.day); break;
      }

      final lookbackYears = _lookbackYearsForTimeframe(_selectedTimeframe);
      startDate = DateTime(endDate.year - lookbackYears, endDate.month, endDate.day);

      final startStr = "${startDate.year}-${startDate.month.toString().padLeft(2, '0')}-${startDate.day.toString().padLeft(2, '0')}";
      final endStr = "${endDate.year}-${endDate.month.toString().padLeft(2, '0')}-${endDate.day.toString().padLeft(2, '0')}";
      final baseOptimizationFields = {
        'optimization_max_weight': _selectedMaxWeight,
        'optimization_portfolios': _selectedPortfolios,
        'optimization_timeframe': _selectedTimeframe,
        'optimization_lookback_years': lookbackYears,
      };
      final rebalanceSimulationFields = {
        ...baseOptimizationFields,
        'rebalance_interval_months': _selectedRebalanceMonths,
        'rebalance_label': _selectedRebalanceLabel,
      };

      void queueRebalancedPortfolio({
        required String selectedType,
        required String savedType,
        required String portfolioKey,
      }) {
        if (!typesToSave.contains(selectedType)) return;

        final data = _rebalancedPortfolioForSave(portfolioKey);
        if (data == null) return;

        batch.set(userPortfoliosRef.doc(), {
          'type': savedType,
          ...data,
          'train_start_date': startStr,
          'train_end_date': endStr,
          'timestamp': FieldValue.serverTimestamp(),
          ...rebalanceSimulationFields,
        });
      }

      if (typesToSave.contains('Max Sharpe')) {
        final weights = _weightsFromOptimizedPortfolio(maxSharpe!);
        batch.set(userPortfoliosRef.doc(), {
          'type': 'Max Sharpe',
          'tickers': weights.keys.toList(),
          'return': maxSharpe!['y'],
          'volatility': maxSharpe!['x'],
          'sharpe': maxSharpe!['sharpe'],
          'weights': weights,
          'train_start_date': startStr, 
          'train_end_date': endStr,     
          'timestamp': FieldValue.serverTimestamp(),
          ...baseOptimizationFields,
        });
      }

      if (typesToSave.contains('Min Risk')) {
        final weights = _weightsFromOptimizedPortfolio(minVol!);
        batch.set(userPortfoliosRef.doc(), {
          'type': 'Min Risk',
          'tickers': weights.keys.toList(),
          'return': minVol!['y'],
          'volatility': minVol!['x'],
          'weights': weights,
          'train_start_date': startStr, 
          'train_end_date': endStr,     
          'timestamp': FieldValue.serverTimestamp(),
          ...baseOptimizationFields,
        });
      }

      if (typesToSave.contains('Max Sortino')) {
        final weights = _weightsFromOptimizedPortfolio(maxSortino!);
        batch.set(userPortfoliosRef.doc(), {
          'type': 'Max Sortino',
          'tickers': weights.keys.toList(),
          'return': maxSortino!['y'],
          'volatility': maxSortino!['x'],
          'sortino': maxSortino!['sortino'],
          'weights': weights,
          'train_start_date': startStr, 
          'train_end_date': endStr,     
          'timestamp': FieldValue.serverTimestamp(),
          ...baseOptimizationFields,
        });
      }

      queueRebalancedPortfolio(
        selectedType: 'Rebalanced Max Sharpe',
        savedType: 'Rebalanced Max Sharpe',
        portfolioKey: 'max_sharpe',
      );
      queueRebalancedPortfolio(
        selectedType: 'Rebalanced Min Risk',
        savedType: 'Rebalanced Min Volatility',
        portfolioKey: 'min_vol',
      );
      queueRebalancedPortfolio(
        selectedType: 'Rebalanced Max Sortino',
        savedType: 'Rebalanced Max Sortino',
        portfolioKey: 'max_sortino',
      );

      try {
        await batch.commit();
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("${typesToSave.length} portfolio(s) saved to history!")));
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Database error: $e")));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    bool isWideScreen = MediaQuery.of(context).size.width > 900;

    return Scaffold(
      appBar: AppBar(
        title: const Text(""),
        leading: IconButton(
          icon: Icon(showSimulation ? Icons.close : Icons.arrow_back),
          onPressed: () {
            if (showSimulation) {
              setState(() => showSimulation = false);
            } else {
              Navigator.pushReplacement(
                context, MaterialPageRoute(builder: (context) => const WelcomeScreen())
              );
            }
          },
        ),
      ),
      body: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 1200),
          child: showSimulation 
              ? _buildSimulationView(isWideScreen) 
              : _buildInputView(isWideScreen),
        ),
      ),
    );
  }

  Widget _buildInputView(bool isWide) {
    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.only(bottom: 20),
            child: Column(
              children: [
                _buildInputSection(),
                _buildTickerArea(),
                const SizedBox(height: 15),
                _buildSettingsRow(),
                const SizedBox(height: 10),
                _buildModelSettingsRow(isWide),
                const SizedBox(height: 10),
                _buildRebalanceSettings(isWide),
                const SizedBox(height: 10),
                _buildCustomPortfolioSection(), 
                const SizedBox(height: 20),
                _buildSavedPortfoliosSection(), 
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(24.0),
          child: SizedBox(
            width: double.infinity, height: 60,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                backgroundColor: Colors.blueAccent,
                foregroundColor: Colors.white,
              ),
              onPressed: isLoading ? null : calculateFrontier,
              child: const Text("Start Simulation", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildRebalanceSettings(bool isWide) {
    final dropdown = DropdownButtonFormField<String>(
      decoration: const InputDecoration(
        labelText: "Rebalance Check",
        border: OutlineInputBorder(),
        isDense: true,
      ),
      value: _selectedRebalanceCode,
      items: _rebalanceChoices.map((choice) {
        return DropdownMenuItem(
          value: choice.code,
          child: Text(choice.label),
        );
      }).toList(),
      onChanged: (value) {
        if (value == null) return;
        setState(() => _selectedRebalanceCode = value);
      },
    );

    final customInput = TextFormField(
      key: ValueKey(_customRebalanceMonths),
      initialValue: _customRebalanceMonths.toString(),
      keyboardType: TextInputType.number,
      decoration: const InputDecoration(
        labelText: "Custom Months",
        border: OutlineInputBorder(),
        isDense: true,
      ),
      onChanged: (value) {
        final months = int.tryParse(value);
        if (months != null && months > 0) {
          _customRebalanceMonths = months;
        }
      },
    );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: isWide
          ? Row(
              children: [
                Expanded(child: dropdown),
                if (_selectedRebalanceCode == 'custom') ...[
                  const SizedBox(width: 8),
                  Expanded(child: customInput),
                ],
              ],
            )
          : Column(
              children: [
                dropdown,
                if (_selectedRebalanceCode == 'custom') ...[
                  const SizedBox(height: 8),
                  customInput,
                ],
              ],
            ),
    );
  }

  Widget _buildModelSettingsRow(bool isWide) {
    final ledoitWolfDropdown = DropdownButtonFormField<bool>(
      decoration: const InputDecoration(
        labelText: "Ledoit-Wolf Shrinkage",
        border: OutlineInputBorder(),
        isDense: true,
      ),
      value: _useLedoitWolf,
      items: const [
        DropdownMenuItem(value: false, child: Text("No")),
        DropdownMenuItem(value: true, child: Text("Yes")),
      ],
      onChanged: (value) {
        if (value == null) return;
        setState(() => _useLedoitWolf = value);
      },
    );

    final returnShrinkageDropdown = DropdownButtonFormField<double>(
      decoration: const InputDecoration(
        labelText: "Return Shrinkage",
        border: OutlineInputBorder(),
        isDense: true,
      ),
      value: _selectedReturnShrinkage,
      items: _returnShrinkageChoices.map((choice) {
        return DropdownMenuItem(
          value: choice.value,
          child: Text(choice.label),
        );
      }).toList(),
      onChanged: (value) {
        if (value == null) return;
        setState(() => _selectedReturnShrinkage = value);
      },
    );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: isWide
          ? Row(
              children: [
                Expanded(child: ledoitWolfDropdown),
                const SizedBox(width: 8),
                Expanded(child: returnShrinkageDropdown),
              ],
            )
          : Column(
              children: [
                ledoitWolfDropdown,
                const SizedBox(height: 8),
                returnShrinkageDropdown,
              ],
            ),
    );
  }

  Widget _buildCustomPortfolioSection() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: Card(
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Column(
          children: [
            ListTile(
              leading: const Icon(Icons.calculate_outlined, color: Colors.blueAccent),
              title: const Text("Test Custom Portfolio", style: TextStyle(fontWeight: FontWeight.bold)),
              subtitle: const Text("Specify custom weights and dates"),
              trailing: Icon(_isCustomPortfolioExpanded ? Icons.expand_less : Icons.expand_more),
              onTap: () {
                setState(() {
                  _isCustomPortfolioExpanded = !_isCustomPortfolioExpanded;
                });
              },
            ),
            AnimatedSize(
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeInOut,
              child: !_isCustomPortfolioExpanded 
                ? const SizedBox.shrink() 
                : Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                icon: const Icon(Icons.date_range, size: 18),
                                label: FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: Text("Start: ${customStartDate.year}-${customStartDate.month.toString().padLeft(2, '0')}-${customStartDate.day.toString().padLeft(2, '0')}"),
                                ),
                                onPressed: () => _selectCustomDate(context, true),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: OutlinedButton.icon(
                                icon: const Icon(Icons.date_range, size: 18),
                                label: FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: Text("End: ${customEndDate.year}-${customEndDate.month.toString().padLeft(2, '0')}-${customEndDate.day.toString().padLeft(2, '0')}"),
                                ),
                                onPressed: () => _selectCustomDate(context, false),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        const Text("Adjust portfolio weights (automatically normalized to 100%)", style: TextStyle(fontSize: 12, color: Colors.grey)),
                        const SizedBox(height: 8),
                        
                        if (selectedTickers.isEmpty) 
                          const Text("Add stocks to adjust weights.", style: TextStyle(fontStyle: FontStyle.italic)),
                        
                        ...selectedTickers.map((ticker) {
                          double defaultVal = selectedTickers.isNotEmpty ? 100.0 / selectedTickers.length : 10.0;
                          double currentVal = customWeights[ticker] ?? defaultVal;

                          return Row(
                            children: [
                              SizedBox(width: 60, child: Text(ticker, style: const TextStyle(fontWeight: FontWeight.bold))),
                              Expanded(
                                child: Slider(
                                  value: currentVal.clamp(0.0, 100.0), 
                                  min: 0,
                                  max: 100,
                                  divisions: 100,
                                  label: "${currentVal.toInt()}",
                                  onChanged: (val) {
                                    setState(() {
                                      customWeights[ticker] = val;
                                    });
                                  },
                                ),
                              ),
                              SizedBox(width: 40, child: Text("${currentVal.toInt()}%")),
                            ],
                          );
                        }),

                        const SizedBox(height: 16),
                        
                        SizedBox(
                          height: 48,
                          child: ElevatedButton.icon(
                            onPressed: isCustomLoading || selectedTickers.isEmpty ? null : saveCustomPortfolio,
                            icon: isCustomLoading 
                                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                                : const Icon(Icons.cloud_upload),
                            label: Text(isCustomLoading ? "Saving..." : "Save Custom Portfolio"),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.green,
                              foregroundColor: Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSimulationView(bool isWide) {
    return Column(
      children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(12.0),
            child: Card(
              elevation: 4,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: _buildChartSection(),
            ),
          ),
        ),
        if (!isLoading && rebalanceError != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Text(
              "Rolling rebalance failed: $rebalanceError",
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.redAccent, fontSize: 12),
            ),
          ),
        if (!isLoading)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                ElevatedButton.icon(
                  onPressed: () => setState(() => showSimulation = false),
                  icon: const Icon(Icons.edit),
                  label: const Text("Adjust Stocks"),
                ),
                ElevatedButton.icon(
                  onPressed: showSavePortfolioDialog,
                  icon: const Icon(Icons.cloud_upload),
                  label: const Text("Save to Cloud"),
                ),
              ],
            ),
          ),
      ],
    );
  }

  List<Map<String, dynamic>> _rebalanceRunsForObjective(String portfolioKey) {
    return rebalanceRuns.map((run) {
      final portfolio = Map<String, dynamic>.from(run[portfolioKey] as Map);
      final runData = <String, dynamic>{
        'number': run['number'],
        'training_start_date': run['training_start_date'],
        'training_end_date': run['training_end_date'],
        'rebalance_date': run['rebalance_date'],
        'start_date': run['start_date'],
        'end_date': run['end_date'],
        'return': portfolio['period_return'] ?? portfolio['total_return'] ?? portfolio['y'],
        'volatility': portfolio['x'],
        'weights': _weightsFromOptimizedPortfolio(portfolio),
        'rebalanced': portfolio['rebalanced'] == true,
        'candidate_score': portfolio['candidate_score'],
        'previous_score': portfolio['previous_score'],
      };

      if (portfolio['sharpe'] != null) {
        runData['sharpe'] = portfolio['sharpe'];
      }
      if (portfolio['sortino'] != null) {
        runData['sortino'] = portfolio['sortino'];
      }
      if (portfolio['cagr'] != null) {
        runData['cagr'] = portfolio['cagr'];
      }
      if (portfolio['total_return'] != null) {
        runData['total_return'] = portfolio['total_return'];
      }

      return runData;
    }).toList();
  }

  Map<String, dynamic>? _rebalancedPortfolioForSave(String portfolioKey) {
    if (rebalanceRuns.isEmpty) return null;

    final runs = _rebalanceRunsForObjective(portfolioKey);
    final rawSummary = rebalanceSummary == null ? null : rebalanceSummary![portfolioKey];
    final summary = rawSummary is Map
        ? Map<String, dynamic>.from(rawSummary)
        : Map<String, dynamic>.from(rebalanceRuns.last[portfolioKey] as Map);
    final latestWeights = _weightsFromOptimizedPortfolio(summary);

    final data = <String, dynamic>{
      'tickers': latestWeights.keys.toList(),
      'weights': latestWeights,
      'return': summary['return'] ?? summary['y'],
      'volatility': summary['volatility'] ?? summary['x'],
      'rebalance_runs': runs,
      'rebalance_strategy': true,
    };

    if (summary['sharpe'] != null) {
      data['sharpe'] = summary['sharpe'];
    }
    if (summary['sortino'] != null) {
      data['sortino'] = summary['sortino'];
    }
    if (summary['cagr'] != null) {
      data['cagr'] = summary['cagr'];
    }
    if (summary['total_return'] != null) {
      data['total_return'] = summary['total_return'];
    }
    if (summary['annualized_return'] != null) {
      data['annualized_return'] = summary['annualized_return'];
    }
    if (summary['max_drawdown'] != null) {
      data['max_drawdown'] = summary['max_drawdown'];
    }

    return data;
  }

  _ChartMarker _markerFromPortfolio({
    required Map<String, dynamic> portfolio,
    required String label,
    required Color color,
    required bool isOriginal,
  }) {
    return _ChartMarker(
      x: (portfolio['x'] as num).toDouble(),
      y: (portfolio['y'] as num).toDouble(),
      label: label,
      color: color,
      isOriginal: isOriginal,
    );
  }

  _ChartMarker? _aggregateRebalanceMarker({
    required String portfolioKey,
    required String label,
    required Color color,
  }) {
    final rawSummary = rebalanceSummary == null ? null : rebalanceSummary![portfolioKey];
    if (rawSummary is! Map) return null;
    final summary = Map<String, dynamic>.from(rawSummary);

    return _ChartMarker(
      x: (summary['x'] as num).toDouble(),
      y: (summary['y'] as num).toDouble(),
      label: label,
      color: color,
      isOriginal: false,
    );
  }

  List<_ChartMarker> _chartMarkers() {
    final markers = <_ChartMarker>[];

    if (maxSharpe != null) {
      markers.add(_markerFromPortfolio(
        portfolio: maxSharpe!,
        label: 'SHA',
        color: Colors.red,
        isOriginal: true,
      ));
    }
    if (minVol != null) {
      markers.add(_markerFromPortfolio(
        portfolio: minVol!,
        label: 'VAR',
        color: Colors.blue,
        isOriginal: true,
      ));
    }
    if (maxSortino != null) {
      markers.add(_markerFromPortfolio(
        portfolio: maxSortino!,
        label: 'SOR',
        color: Colors.purple,
        isOriginal: true,
      ));
    }

    final rebalancedMarkers = [
      _aggregateRebalanceMarker(
        portfolioKey: 'max_sharpe',
        label: "SHA'",
        color: Colors.red,
      ),
      _aggregateRebalanceMarker(
        portfolioKey: 'min_vol',
        label: "VAR'",
        color: Colors.blue,
      ),
      _aggregateRebalanceMarker(
        portfolioKey: 'max_sortino',
        label: "SOR'",
        color: Colors.purple,
      ),
    ];

    markers.addAll(rebalancedMarkers.whereType<_ChartMarker>());
    return markers;
  }

  bool _markersVisuallyOverlap(
    _ChartMarker a,
    _ChartMarker b,
    double xRange,
    double yRange,
  ) {
    final normalizedXDistance =
        xRange == 0 ? 0.0 : (a.x - b.x).abs() / xRange;
    final normalizedYDistance =
        yRange == 0 ? 0.0 : (a.y - b.y).abs() / yRange;

    return normalizedXDistance <= 0.018 && normalizedYDistance <= 0.018;
  }

  List<String> _chartMarkerLabels(
    List<_ChartMarker> markers,
    double xRange,
    double yRange,
  ) {
    final labels = List<String>.filled(markers.length, '');
    final used = List<bool>.filled(markers.length, false);

    for (var i = 0; i < markers.length; i++) {
      if (used[i]) continue;

      used[i] = true;
      final groupedLabels = <String>[markers[i].label];

      for (var j = i + 1; j < markers.length; j++) {
        if (used[j]) continue;
        if (_markersVisuallyOverlap(markers[i], markers[j], xRange, yRange)) {
          used[j] = true;
          groupedLabels.add(markers[j].label);
        }
      }

      labels[i] = groupedLabels.join(' / ');
    }

    return labels;
  }

  Widget _buildInputSection() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: RawAutocomplete<String>(
        focusNode: _focusNode,
        textEditingController: _tickerController,
        optionsBuilder: (TextEditingValue textEditingValue) {
          final input = textEditingValue.text.toUpperCase().trim();
          if (input.isEmpty) return const Iterable<String>.empty();
          return _tickerUniverse.where((ticker) {
            return ticker.contains(input) && !selectedTickers.contains(ticker);
          });
        },
        onSelected: (String selection) {
          setState(() {
            selectedTickers.add(selection);
            _syncCustomWeights(); 
            _ensureSelectedMaxWeightIsValid();
          });
          _tickerController.clear(); 
          _focusNode.requestFocus(); 
        },
        fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
          return TextField(
            controller: controller,
            focusNode: focusNode,
            onSubmitted: (value) {
              if (value.isNotEmpty) {
                final newTicker = value.toUpperCase().trim();
                if (!selectedTickers.contains(newTicker)) {
                  setState(() {
                    selectedTickers.add(newTicker);
                    _syncCustomWeights(); 
                    _ensureSelectedMaxWeightIsValid();
                    controller.clear();
                  });
                }
              }
              onFieldSubmitted();
            },
            decoration: InputDecoration(
              isDense: true, 
              labelText: "Add stock symbol (e.g. NVDA)",
              suffixIcon: IconButton(
                icon: const Icon(Icons.add_circle),
                onPressed: () {
                  if (controller.text.isNotEmpty) {
                    final newTicker = controller.text.toUpperCase().trim();
                    if (!selectedTickers.contains(newTicker)) {
                      setState(() {
                        selectedTickers.add(newTicker);
                        _syncCustomWeights(); 
                        _ensureSelectedMaxWeightIsValid();
                        controller.clear();
                      });
                    }
                  }
                },
              ),
              border: const OutlineInputBorder(),
            ),
          );
        },
        optionsViewBuilder: (context, onSelected, options) {
          return Align(
            alignment: Alignment.topLeft,
            child: Material(
              elevation: 4.0,
              borderRadius: BorderRadius.circular(8),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 200, maxWidth: 300),
                child: ListView.builder(
                  padding: EdgeInsets.zero,
                  shrinkWrap: true,
                  itemCount: options.length,
                  itemBuilder: (BuildContext context, int index) {
                    final String option = options.elementAt(index);
                    return InkWell(
                      onTap: () => onSelected(option),
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Text(option, style: const TextStyle(fontWeight: FontWeight.bold)),
                      ),
                    );
                  },
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildTickerArea() {
    return Container(
      constraints: const BoxConstraints(maxHeight: 140), 
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.only(bottom: 8.0), 
          child: Wrap(
            spacing: 8, runSpacing: 4,
            children: [
              ...selectedTickers.map((ticker) => Chip(
                visualDensity: VisualDensity.compact,
                label: Text(ticker, style: const TextStyle(fontSize: 12)),
                onDeleted: () => setState(() {
                  selectedTickers.remove(ticker);
                  _syncCustomWeights(); 
                  _ensureSelectedMaxWeightIsValid();
                }),
              )),
              if (selectedTickers.isNotEmpty)
                ActionChip(
                  visualDensity: VisualDensity.compact, 
                  label: const Text("Clear all", style: TextStyle(color: Colors.red, fontSize: 12)),
                  onPressed: () => setState(() {
                    selectedTickers.clear();
                    _syncCustomWeights(); 
                    _ensureSelectedMaxWeightIsValid();
                  }),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSettingsRow() {
    final availableWeightOptions = _availableWeightOptions;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      child: Row(
        children: [
          Expanded(
            child: DropdownButtonFormField<double>(
              decoration: const InputDecoration(labelText: "Max Weight", border: OutlineInputBorder(), isDense: true),
              value: _selectedMaxWeight,
              items: availableWeightOptions.map((w) => DropdownMenuItem(value: w, child: Text("${(w * 100).toInt()}%"))).toList(),
              onChanged: (val) => setState(() => _selectedMaxWeight = val!),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: DropdownButtonFormField<String>(
              decoration: const InputDecoration(labelText: "Time Horizon", border: OutlineInputBorder(), isDense: true),
              value: _selectedTimeframe,
              items: _timeframeOptions.map((t) => DropdownMenuItem(value: t, child: Text(t))).toList(),
              onChanged: (val) => setState(() => _selectedTimeframe = val!),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: DropdownButtonFormField<int>(
              decoration: const InputDecoration(labelText: "Portfolios", border: OutlineInputBorder(), isDense: true),
              value: _selectedPortfolios,
              items: _portfolioOptions.map((p) => DropdownMenuItem(value: p, child: Text(p.toString()))).toList(),
              onChanged: (val) => setState(() => _selectedPortfolios = val!),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChartSection() {
    if (scatterSpots.isEmpty && !isLoading) return const Center(child: Text("No data"));
    if (isLoading) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              "Simulation started. Results can take 90-120 seconds to appear.",
              textAlign: TextAlign.center,
            ),
            SizedBox(height: 16),
            CircularProgressIndicator(),
          ],
        ),
      );
    }

    double minXVal = scatterSpots.map((s) => s.x).reduce(min);
    double maxXVal = scatterSpots.map((s) => s.x).reduce(max);
    double minYVal = scatterSpots.map((s) => s.y).reduce(min);
    double maxYVal = scatterSpots.map((s) => s.y).reduce(max);

    if (maxSharpe != null) {
      minXVal = min(minXVal, (maxSharpe!['x'] as num).toDouble());
      maxXVal = max(maxXVal, (maxSharpe!['x'] as num).toDouble());
      minYVal = min(minYVal, (maxSharpe!['y'] as num).toDouble());
      maxYVal = max(maxYVal, (maxSharpe!['y'] as num).toDouble());
    }

    if (minVol != null) {
      minXVal = min(minXVal, (minVol!['x'] as num).toDouble());
      maxXVal = max(maxXVal, (minVol!['x'] as num).toDouble());
      minYVal = min(minYVal, (minVol!['y'] as num).toDouble());
      maxYVal = max(maxYVal, (minVol!['y'] as num).toDouble());
    }

    if (maxSortino != null) {
      minXVal = min(minXVal, (maxSortino!['x'] as num).toDouble());
      maxXVal = max(maxXVal, (maxSortino!['x'] as num).toDouble());
      minYVal = min(minYVal, (maxSortino!['y'] as num).toDouble());
      maxYVal = max(maxYVal, (maxSortino!['y'] as num).toDouble());
    }

    final chartMarkers = _chartMarkers();
    for (final marker in chartMarkers) {
      minXVal = min(minXVal, marker.x);
      maxXVal = max(maxXVal, marker.x);
      minYVal = min(minYVal, marker.y);
      maxYVal = max(maxYVal, marker.y);
    }

    final markerLabels = _chartMarkerLabels(
      chartMarkers,
      maxXVal - minXVal,
      maxYVal - minYVal,
    );

    double xPadding = (maxXVal - minXVal) * 0.05;
    double yPadding = (maxYVal - minYVal) * 0.05;
    
    if (xPadding == 0) xPadding = 0.05;
    if (yPadding == 0) yPadding = 0.05;

    return Column(
      children: [
        const Padding(
          padding: EdgeInsets.only(top: 16.0),
          child: Text("", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(right: 20, left: 10, top: 20, bottom: 10),
            child: ScatterChart(
              ScatterChartData(
                minX: minXVal - xPadding,
                maxX: maxXVal + xPadding,
                minY: minYVal - yPadding,
                maxY: maxYVal + yPadding,
                clipData: const FlClipData.none(),
                scatterLabelSettings: ScatterLabelSettings(
                  showLabel: true,
                  getLabelFunction: (spotIndex, spot) {
                    final markerIndex = spotIndex - scatterSpots.length;
                    if (markerIndex < 0 || markerIndex >= chartMarkers.length) {
                      return '';
                    }
                    return markerLabels[markerIndex];
                  },
                  getLabelTextStyleFunction: (spotIndex, spot) {
                    final markerIndex = spotIndex - scatterSpots.length;
                    if (markerIndex < 0 || markerIndex >= chartMarkers.length) {
                      return null;
                    }
                    final marker = chartMarkers[markerIndex];
                    return TextStyle(
                      color: marker.color.withOpacity(marker.isOriginal ? 0.9 : 1.0),
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    );
                  },
                ),
                scatterSpots: [
                  ...scatterSpots,
                  ...chartMarkers.map((marker) {
                    return ScatterSpot(
                      marker.x,
                      marker.y,
                      dotPainter: FlDotCirclePainter(
                        radius: marker.isOriginal ? 7.0 : 9.0,
                        color: marker.color.withOpacity(marker.isOriginal ? 0.55 : 0.95),
                        strokeWidth: marker.isOriginal ? 1.0 : 2.0,
                        strokeColor: Colors.white,
                      ),
                    );
                  }),
                ],
                titlesData: FlTitlesData(
                  bottomTitles: AxisTitles(
                    axisNameWidget: const Text("Annual Volatility", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                    axisNameSize: 25,
                    sideTitles: SideTitles(
                      showTitles: true, 
                      reservedSize: 30, 
                      interval: 0.05,
                      getTitlesWidget: (v, m) {
                        if (v == m.min || v == m.max) return const SizedBox.shrink();
                        return Padding(
                          padding: const EdgeInsets.only(top: 8.0),
                          child: Text(v.toStringAsFixed(2), style: const TextStyle(fontSize: 10)),
                        );
                      },
                    ),
                  ),
                  leftTitles: AxisTitles(
                    axisNameWidget: const Text("Annual Return", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                    axisNameSize: 25,
                    sideTitles: SideTitles(
                      showTitles: true, 
                      reservedSize: 40,
                      interval: 0.05,
                      getTitlesWidget: (v, m) {
                        if (v == m.min || v == m.max) return const SizedBox.shrink();
                        return Text(v.toStringAsFixed(2), style: const TextStyle(fontSize: 10));
                      },
                    ),
                  ),
                  topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                ),
                gridData: FlGridData(
                  show: true, horizontalInterval: 0.05, verticalInterval: 0.05,
                  getDrawingHorizontalLine: (v) => FlLine(color: Colors.grey.withOpacity(0.1)),
                  getDrawingVerticalLine: (v) => FlLine(color: Colors.grey.withOpacity(0.1)),
                ),
                borderData: FlBorderData(show: true, border: Border.all(color: Colors.black12)),
              ),
            ),
          ),
        ),
        _buildLegend(),
      ],
    );
  }

  Widget _buildLegend() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _legendItem(Colors.red, "SHA / SHA'"),
          const SizedBox(width: 20),
          _legendItem(Colors.blue, "VAR / VAR'"),
          const SizedBox(width: 20),
          _legendItem(Colors.purple, "SOR / SOR'"),
        ],
      ),
    );
  }

  Widget _legendItem(Color color, String text) {
    return Row(
      children: [
        Container(width: 12, height: 12, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 6),
        Text(text, style: const TextStyle(fontSize: 12)),
      ],
    );
  }

  String _savedPortfolioSubtitle(Map<String, dynamic> data) {
    final annualReturn = (data['return'] as num?)?.toDouble();
    final returnText = annualReturn == null
        ? "Annual Return: N/A"
        : "Annual Return: ${(annualReturn * 100).toStringAsFixed(1)}%";
    final interval = data['rebalance_interval_months'];
    if (interval is num && interval > 0) {
      final label = data['rebalance_label']?.toString() ?? "Every $interval months";
      return "$returnText | Rebalance: $label";
    }
    return returnText;
  }

  Widget _buildSavedPortfoliosSection() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const Padding(
        padding: EdgeInsets.all(16.0),
        child: Center(child: Text("Log in to see saved portfolios")),
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min, 
      children: [
        const Divider(),
        StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance
              .collection('users')
              .doc(user.uid)
              .collection('saved_portfolios')
              .orderBy('timestamp', descending: true)
              .snapshots(),
          builder: (context, snapshot) {
            if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
            
            final docs = snapshot.data!.docs;
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16.0),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      "My Portfolios",
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
                if (docs.isEmpty)
                  const Center(
                    child: Padding(
                      padding: EdgeInsets.all(8.0),
                      child: Text(
                        "No portfolios saved yet",
                        style: TextStyle(fontSize: 12),
                      ),
                    ),
                  )
                else
                  ListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: docs.length,
                    itemBuilder: (context, index) {
                      final data = docs[index].data() as Map<String, dynamic>;
                      final String portfolioType = data['type'] ?? 'Portfolio';
                      final bool isMaxSharpe = portfolioType.contains('Sharpe');
                      final bool isMaxSortino = portfolioType.contains('Sortino');

                      return ListTile(
                        dense: true,
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
                          size: 20,
                        ),
                        title: Text("$portfolioType: ${data['tickers'].join(', ')}"),
                        subtitle: Text(_savedPortfolioSubtitle(data)),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline, size: 18),
                          onPressed: () => docs[index].reference.delete(),
                        ),
                        onTap: () => _showWeightsDialog(context, data),
                      );
                    },
                  ),
              ],
            );
          },
        ),
      ],
    );
  }

  void _showWeightsDialog(BuildContext context, Map<String, dynamic> data) {
    final weights = Map<String, dynamic>.from(data['weights'] as Map);
    final rawRuns = data['rebalance_runs'];
    final rebalanceHistory = rawRuns is Iterable
        ? rawRuns.map((run) => Map<String, dynamic>.from(run as Map)).toList()
        : <Map<String, dynamic>>[];

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
              Text("${((e.value as num).toDouble() * 100).toStringAsFixed(1)}%"),
            ],
          ),
        );
      }).toList();
    }

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text("${data['type'] ?? 'Portfolio'} Allocation"),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
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
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
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
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Close")),
        ],
      ),
    );
  }
}

class _RebalanceChoice {
  const _RebalanceChoice({
    required this.code,
    required this.label,
    required this.months,
  });

  final String code;
  final String label;
  final int? months;
}

class _ReturnShrinkageChoice {
  const _ReturnShrinkageChoice({
    required this.value,
    required this.label,
  });

  final double value;
  final String label;
}

class _ChartMarker {
  const _ChartMarker({
    required this.x,
    required this.y,
    required this.label,
    required this.color,
    required this.isOriginal,
  });

  final double x;
  final double y;
  final String label;
  final Color color;
  final bool isOriginal;
}
