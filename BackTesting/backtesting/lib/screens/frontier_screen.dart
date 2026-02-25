import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:fl_chart/fl_chart.dart';
import 'package:backtesting/screens/welcome_screen.dart';

class FrontierScreen extends StatefulWidget {
  const FrontierScreen({super.key});

  @override
  State<FrontierScreen> createState() => _FrontierScreenState();
}

class _FrontierScreenState extends State<FrontierScreen> {
  // --- STATE VARIABLES ---
  final TextEditingController _tickerController = TextEditingController();
  List<String> selectedTickers = ['AAPL', 'MSFT', 'GOOGL', 'TSLA'];
  List<Map<String, dynamic>> savedPortfolios = [];
  
  List<ScatterSpot> scatterSpots = [];
  Map<String, dynamic>? maxSharpe;
  Map<String, dynamic>? minVol;
  
  bool isLoading = false;
  bool showSimulation = false; // Flag to maximize chart area

  // --- API LOGIC ---
  Future<void> calculateFrontier() async {
    if (selectedTickers.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please add at least one ticker.")),
      );
      return;
    }
    
    setState(() {
      isLoading = true;
      showSimulation = true; // Expand chart area immediately
    });

    final tickerString = selectedTickers.join(',');
    final url = Uri.parse('https://efficientfrontier.onrender.com/optimize?tickers=$tickerString');
    
    try {
      final response = await http.get(url).timeout(const Duration(seconds: 45));
     // Inside your calculateFrontier function, after data is decoded:
    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      
      List<ScatterSpot> rawSpots = (data['scatter_points'] as List).map((p) {
        return ScatterSpot((p['x'] as num).toDouble(), (p['y'] as num).toDouble());
      }).toList();

      // Sort by Y (Returns) and remove the top 5% extreme outliers
      rawSpots.sort((a, b) => a.y.compareTo(b.y));
      int limit = (rawSpots.length * 0.95).toInt();
      List<ScatterSpot> filteredSpots = rawSpots.sublist(0, limit);

      setState(() {
        scatterSpots = filteredSpots.map((s) => ScatterSpot(
          s.x, s.y,
          dotPainter: FlDotCirclePainter(radius: 1, color: Colors.blueGrey.withOpacity(0.3))
        )).toList();
        
        maxSharpe = data['max_sharpe'];
        minVol = data['min_vol'];
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

  void savePortfolio() {
    if (maxSharpe != null) {
      setState(() {
        savedPortfolios.add({
          'tickers': List.from(selectedTickers),
          'return': maxSharpe!['y'],
          'weights': maxSharpe!['weights'],
        });
      });
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Portfolio Saved!")));
    }
  }

  @override
  Widget build(BuildContext context) {
    bool isWideScreen = MediaQuery.of(context).size.width > 900;

    return Scaffold(
      appBar: AppBar(
        title: const Text("Portfolio Optimizer"),
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

  // --- VIEW 1: INPUT & CONFIGURATION ---
  Widget _buildInputView(bool isWide) {
    return Column(
      children: [
        _buildInputSection(),
        _buildTickerArea(),
        const Spacer(),
        _buildSavedPortfoliosSection(),
        Padding(
          padding: const EdgeInsets.all(24.0),
          child: SizedBox(
            width: double.infinity,
            height: 60,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                backgroundColor: Colors.blueAccent,
                foregroundColor: Colors.white,
              ),
              onPressed: isLoading ? null : calculateFrontier,
              child: const Text("Run Simulation", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            ),
          ),
        ),
      ],
    );
  }

  // --- VIEW 2: FULL SCREEN RESULT ---
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
                OutlinedButton.icon(
                  onPressed: () => setState(() => showSimulation = false),
                  icon: const Icon(Icons.edit),
                  label: const Text("Adjust Tickers"),
                ),
                ElevatedButton.icon(
                  onPressed: savePortfolio,
                  icon: const Icon(Icons.save),
                  label: const Text("Save Optimal Portfolio"),
                ),
              ],
            ),
          ),
      ],
    );
  }

  // --- COMPONENT WIDGETS ---

  Widget _buildInputSection() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: TextField(
        controller: _tickerController,
        decoration: InputDecoration(
          isDense: true,
          labelText: "Add Ticker (e.g. NVDA, AMZN)",
          suffixIcon: IconButton(
            icon: const Icon(Icons.add_circle),
            onPressed: () {
              if (_tickerController.text.isNotEmpty) {
                setState(() {
                  selectedTickers.add(_tickerController.text.toUpperCase().trim());
                  _tickerController.clear();
                });
              }
            },
          ),
          border: const OutlineInputBorder(),
        ),
      ),
    );
  }

  Widget _buildTickerArea() {
    return Container(
      constraints: const BoxConstraints(maxHeight: 120),
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: SingleChildScrollView(
        child: Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            ...selectedTickers.map((ticker) => Chip(
              visualDensity: VisualDensity.compact,
              label: Text(ticker, style: const TextStyle(fontSize: 12)),
              onDeleted: () => setState(() => selectedTickers.remove(ticker)),
            )),
            if (selectedTickers.isNotEmpty)
              ActionChip(
                label: const Text("Clear All", style: TextStyle(color: Colors.red, fontSize: 12)),
                onPressed: () => setState(() => selectedTickers.clear()),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildChartSection() {
    return isLoading 
      ? const Center(child: CircularProgressIndicator())
      : Column(
          children: [
            const Padding(
              padding: EdgeInsets.only(top: 16.0),
              child: Text("Efficient Frontier Analysis", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(right: 20, left: 10, top: 20, bottom: 10),
                child: ScatterChart(
                  ScatterChartData(
                    // 1. ADD PADDING TO AXES
                    // This calculates the range of your data and adds a 5-10% buffer
                    minX: (scatterSpots.map((s) => s.x).reduce((a, b) => a < b ? a : b)) * 0.95,
                    maxX: (scatterSpots.map((s) => s.x).reduce((a, b) => a > b ? a : b)) * 1.05,
                    minY: (scatterSpots.map((s) => s.y).reduce((a, b) => a < b ? a : b)) * 0.95,
                    maxY: (scatterSpots.map((s) => s.y).reduce((a, b) => a > b ? a : b)) * 1.05,

                    // 2. DISABLE CLIPPING
                    // Changing this to false allows the large dots to be fully visible even near the edge
                    clipData: const FlClipData.none(), 

                    scatterSpots: [
                      ...scatterSpots,
                      if (maxSharpe != null)
                        ScatterSpot(
                          (maxSharpe!['x'] as num).toDouble(), 
                          (maxSharpe!['y'] as num).toDouble(),
                          dotPainter: FlDotCirclePainter(radius: 8, color: Colors.red, strokeWidth: 2, strokeColor: Colors.white),
                        ),
                      if (minVol != null)
                        ScatterSpot(
                          (minVol!['x'] as num).toDouble(), 
                          (minVol!['y'] as num).toDouble(),
                          dotPainter: FlDotCirclePainter(radius: 8, color: Colors.blue, strokeWidth: 2, strokeColor: Colors.white),
                        ),
                    ],
                    titlesData: FlTitlesData(
                      bottomTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          reservedSize: 30,
                          interval: 0.05,
                          getTitlesWidget: (value, meta) {
                            if (value == meta.min) return const SizedBox.shrink();
                            return Text(value.toStringAsFixed(2), style: const TextStyle(fontSize: 10));
                          },
                        ),
                      ),
                      leftTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          reservedSize: 40,
                          getTitlesWidget: (value, meta) => Text(value.toStringAsFixed(2), style: const TextStyle(fontSize: 10)),
                        ),
                      ),
                      topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                      rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    ),
                    gridData: FlGridData(
                      show: true,
                      horizontalInterval: 0.05,
                      verticalInterval: 0.05,
                      getDrawingHorizontalLine: (value) => FlLine(color: Colors.grey.withOpacity(0.1), strokeWidth: 1),
                      getDrawingVerticalLine: (value) => FlLine(color: Colors.grey.withOpacity(0.1), strokeWidth: 1),
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
          _legendItem(Colors.blue, "Min Risk"),
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
    if (savedPortfolios.isEmpty) return const SizedBox.shrink();
    return Expanded(
      child: Column(
        children: [
          const Divider(),
          const Text("Saved Portfolios", style: TextStyle(fontWeight: FontWeight.bold)),
          Expanded(
            child: ListView.builder(
              itemCount: savedPortfolios.length,
              itemBuilder: (context, index) {
                final port = savedPortfolios[index];
                return ListTile(
                  dense: true,
                  title: Text(port['tickers'].join(', ')),
                  subtitle: Text("Return: ${(port['return'] * 100).toStringAsFixed(1)}%"),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _showWeightsDialog(context, port),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  void _showWeightsDialog(BuildContext context, Map<String, dynamic> port) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Optimal Weights"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: (port['weights'] as Map<String, dynamic>).entries.map((e) => 
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