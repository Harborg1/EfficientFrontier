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
  String _selectedTimeframe = '5 år';
  
  final List<double> _weightOptions = [0.10, 0.20, 0.30, 0.40, 0.50, 1.00];
  final List<int> _portfolioOptions = [20000, 40000, 70000, 100000];
  final List<String> _timeframeOptions = ['1 år', '3 år', '5 år', '10 år'];
  
  List<ScatterSpot> scatterSpots = [];
  Map<String, dynamic>? maxSharpe;
  Map<String, dynamic>? minVol;
  Map<String, dynamic>? maxSortino;

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
      isLoading = true;
      showSimulation = true;
    });

    final today = DateTime.now();
    final endDate = DateTime(today.year - 1, today.month, today.day); 
    DateTime startDate;
    switch (_selectedTimeframe) {
      case '1 år': startDate = DateTime(endDate.year - 1, endDate.month, endDate.day); break;
      case '3 år': startDate = DateTime(endDate.year - 3, endDate.month, endDate.day); break;
      case '10 år': startDate = DateTime(endDate.year - 10, endDate.month, endDate.day); break;
      case '5 år':
      default: startDate = DateTime(endDate.year - 5, endDate.month, endDate.day); break;
    }

    final startStr = "${startDate.year}-${startDate.month.toString().padLeft(2, '0')}-${startDate.day.toString().padLeft(2, '0')}";
    final endStr = "${endDate.year}-${endDate.month.toString().padLeft(2, '0')}-${endDate.day.toString().padLeft(2, '0')}";
    final tickerString = selectedTickers.join(',');
    
    final url = Uri.parse(
      'https://efficientfrontier.onrender.com/optimize'
      '?tickers=$tickerString'
      '&max_weight=$_selectedMaxWeight'
      '&start_date=$startStr'
      '&end_date=$endStr'
      '&num_portfolios=$_selectedPortfolios'
      '&t=${DateTime.now().millisecondsSinceEpoch}'
    );
    
    try {
      final response = await http.get(url).timeout(const Duration(seconds: 120));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        
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
          isLoading = false;
        });
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
              content: Column(
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
                ],
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
        case '1 år': startDate = DateTime(endDate.year - 1, endDate.month, endDate.day); break;
        case '3 år': startDate = DateTime(endDate.year - 3, endDate.month, endDate.day); break;
        case '10 år': startDate = DateTime(endDate.year - 10, endDate.month, endDate.day); break;
        case '5 år':
        default: startDate = DateTime(endDate.year - 5, endDate.month, endDate.day); break;
      }

      final startStr = "${startDate.year}-${startDate.month.toString().padLeft(2, '0')}-${startDate.day.toString().padLeft(2, '0')}";
      final endStr = "${endDate.year}-${endDate.month.toString().padLeft(2, '0')}-${endDate.day.toString().padLeft(2, '0')}";

      if (typesToSave.contains('Max Sharpe')) {
        batch.set(userPortfoliosRef.doc(), {
          'type': 'Max Sharpe',
          'tickers': List.from(selectedTickers),
          'return': maxSharpe!['y'],
          'volatility': maxSharpe!['x'],
          'sharpe': maxSharpe!['sharpe'],
          'weights': maxSharpe!['weights'],
          'train_start_date': startStr, 
          'train_end_date': endStr,     
          'timestamp': FieldValue.serverTimestamp(),
        });
      }

      if (typesToSave.contains('Min Risk')) {
        batch.set(userPortfoliosRef.doc(), {
          'type': 'Min Risk',
          'tickers': List.from(selectedTickers),
          'return': minVol!['y'],
          'volatility': minVol!['x'],
          'weights': minVol!['weights'],
          'train_start_date': startStr, 
          'train_end_date': endStr,     
          'timestamp': FieldValue.serverTimestamp(),
        });
      }

      if (typesToSave.contains('Max Sortino')) {
        batch.set(userPortfoliosRef.doc(), {
          'type': 'Max Sortino',
          'tickers': List.from(selectedTickers),
          'return': maxSortino!['y'],
          'volatility': maxSortino!['x'],
          'sortino': maxSortino!['sortino'],
          'weights': maxSortino!['weights'],
          'train_start_date': startStr, 
          'train_end_date': endStr,     
          'timestamp': FieldValue.serverTimestamp(),
        });
      }

      try {
        await batch.commit();
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("${typesToSave.length} portfolio(s) saved to Firestore!")));
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
        title: const Text("Portfolio Optimization"),
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
        if (!isLoading)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16.0),
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
                }),
              )),
              if (selectedTickers.isNotEmpty)
                ActionChip(
                  visualDensity: VisualDensity.compact, 
                  label: const Text("Clear all", style: TextStyle(color: Colors.red, fontSize: 12)),
                  onPressed: () => setState(() {
                    selectedTickers.clear();
                    _syncCustomWeights(); 
                  }),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSettingsRow() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      child: Row(
        children: [
          Expanded(
            child: DropdownButtonFormField<double>(
              decoration: const InputDecoration(labelText: "Max Weight", border: OutlineInputBorder(), isDense: true),
              value: _selectedMaxWeight,
              items: _weightOptions.map((w) => DropdownMenuItem(value: w, child: Text("${(w * 100).toInt()}%"))).toList(),
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
    if (isLoading) return const Center(child: CircularProgressIndicator());

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
                scatterSpots: [
                  ...scatterSpots,
                  if (maxSharpe != null)
                    ScatterSpot(
                      (maxSharpe!['x'] as num).toDouble(), (maxSharpe!['y'] as num).toDouble(),
                      dotPainter: FlDotCirclePainter(radius: 8, color: Colors.red, strokeWidth: 2, strokeColor: Colors.white),
                    ),
                  if (minVol != null)
                    ScatterSpot(
                      (minVol!['x'] as num).toDouble(), (minVol!['y'] as num).toDouble(),
                      dotPainter: FlDotCirclePainter(radius: 8, color: Colors.blue, strokeWidth: 2, strokeColor: Colors.white),
                    ),
                  if (maxSortino != null)
                    ScatterSpot(
                      (maxSortino!['x'] as num).toDouble(), (maxSortino!['y'] as num).toDouble(),
                      dotPainter: FlDotCirclePainter(radius: 8, color: Colors.purple, strokeWidth: 2, strokeColor: Colors.white),
                    ),
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
          _legendItem(Colors.red, "Max Sharpe"),
          const SizedBox(width: 20),
          _legendItem(Colors.blue, "Min Volatility"),
          const SizedBox(width: 20),
          _legendItem(Colors.green, "Max Sortino"),
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
        const Text("My Portfolios", style: TextStyle(fontWeight: FontWeight.bold)),
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
            if (docs.isEmpty) return const Center(child: Padding(padding: EdgeInsets.all(8.0), child: Text("No portfolios saved yet", style: TextStyle(fontSize: 12))));

            return ListView.builder(
              shrinkWrap: true, 
              physics: const NeverScrollableScrollPhysics(), 
              itemCount: docs.length,
              itemBuilder: (context, index) {
                final data = docs[index].data() as Map<String, dynamic>;
                final bool isMaxSharpe = data['type'] == 'Max Sharpe';
                final bool isMaxSortino = data['type'] == 'Max Sortino';

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
                  title: Text("${data['type']}: ${data['tickers'].join(', ')}"),
                  subtitle: Text("Annual Return: ${(data['return'] * 100).toStringAsFixed(1)}%"),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline, size: 18),
                    onPressed: () => docs[index].reference.delete(),
                  ),
                  onTap: () => _showWeightsDialog(context, data),
                );
              },
            );
          },
        ),
      ],
    );
  }

  void _showWeightsDialog(BuildContext context, Map<String, dynamic> data) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text("${data['type']} Allocation"),
        content: Column(
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
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Close")),
        ],
      ),
    );
  }
}
