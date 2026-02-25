import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:fl_chart/fl_chart.dart';

// IMPORTANT: Adjust this import to match your actual file path
import 'package:backtesting/screens/welcome_screen.dart'; 

// The data structure to hold coordinates from Python
class PortfolioPoint {
  final double x;
  final double y;
  PortfolioPoint(this.x, this.y);

  factory PortfolioPoint.fromJson(Map<String, dynamic> json) {
    return PortfolioPoint(
      (json['x'] as num).toDouble(),
      (json['y'] as num).toDouble(),
    );
  }
}

class FrontierScreen extends StatefulWidget {
  const FrontierScreen({super.key});

  @override
  State<FrontierScreen> createState() => _FrontierScreenState();
}

class _FrontierScreenState extends State<FrontierScreen> {
  List<ScatterSpot> scatterSpots = [];
  PortfolioPoint? maxSharpe;
  PortfolioPoint? minVol;
  bool isLoading = false;

  Future<void> calculateFrontier() async {
    setState(() => isLoading = true);
    
    // API URL - ensure your FastAPI server is running on port 8000
    final url = Uri.parse('https://efficientfrontier.onrender.com/optimize?tickers=AAPL,F,WMT,GOOG,TSLA');
    
    try {
      // OPTIMIZATION: Added a 15-second timeout to prevent infinite loading screens
      final response = await http.get(url).timeout(const Duration(seconds: 15));
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        
        setState(() {
          // Map the 5000 cloud points and assign their specific painter here
          scatterSpots = (data['scatter_points'] as List).map((p) {
            return ScatterSpot(
              (p['x'] as num).toDouble(), 
              (p['y'] as num).toDouble(),
              dotPainter: FlDotCirclePainter(
                radius: 1.5,
                color: Colors.blueGrey.withOpacity(0.4),
                strokeWidth: 0, // Removes the border for the small dots
              ),
            );
          }).toList();
          
          maxSharpe = PortfolioPoint.fromJson(data['max_sharpe']);
          minVol = PortfolioPoint.fromJson(data['min_vol']);
          isLoading = false;
        });
      }
    } catch (e) {
      setState(() => isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Connection Error: Check if server is running.")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Efficient Frontier"),
        // OPTIMIZATION: Added a back button to return to the Welcome Screen
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (context) => const WelcomeScreen()),
            );
          },
        ),
      ),
      body: Column(
        children: [
          const SizedBox(height: 10),
          ElevatedButton(
            onPressed: isLoading ? null : calculateFrontier,
            child: Text(isLoading ? "Analyzing..." : "Run Optimization"),
          ),
          Expanded(
            child: isLoading
                ? const Center(child: CircularProgressIndicator())
                : Padding(
                    padding: const EdgeInsets.all(20),
                    child: ScatterChart(
                      ScatterChartData(
                        scatterSpots: [
                          ...scatterSpots,
                          
                          // Max Sharpe (Red Dot)
                          if (maxSharpe != null) 
                            ScatterSpot(
                              maxSharpe!.x, 
                              maxSharpe!.y,
                              dotPainter: FlDotCirclePainter(
                                radius: 8,
                                color: Colors.red,
                                strokeWidth: 2,
                                strokeColor: Colors.white,
                              ),
                            ),
                            
                          // Min Volatility (Blue Dot)
                          if (minVol != null) 
                            ScatterSpot(
                              minVol!.x, 
                              minVol!.y,
                              dotPainter: FlDotCirclePainter(
                                radius: 8,
                                color: Colors.blue,
                                strokeWidth: 2,
                                strokeColor: Colors.white,
                              ),
                            ),
                        ],
                        
                        // OPTIMIZATION: Cleaned up axes formatting to prevent overlapping text
                        titlesData: FlTitlesData(
                          bottomTitles: AxisTitles(
                            axisNameWidget: const Padding(
                              padding: EdgeInsets.only(top: 8.0),
                              child: Text("Volatility (Risk)", style: TextStyle(fontWeight: FontWeight.bold)),
                            ),
                            sideTitles: SideTitles(
                              showTitles: true, 
                              reservedSize: 40, // More breathing room for numbers
                              getTitlesWidget: (value, meta) {
                                // Forces numbers to 2 decimal places (e.g. 0.24)
                                return Padding(
                                  padding: const EdgeInsets.only(top: 8.0),
                                  child: Text(value.toStringAsFixed(2), style: const TextStyle(fontSize: 11)),
                                );
                              },
                            ),
                          ),
                          leftTitles: AxisTitles(
                            axisNameWidget: const Text("Expected Return", style: TextStyle(fontWeight: FontWeight.bold)),
                            sideTitles: SideTitles(
                              showTitles: true, 
                              reservedSize: 45, // More breathing room
                              getTitlesWidget: (value, meta) {
                                // Forces numbers to 2 decimal places
                                return Text(value.toStringAsFixed(2), style: const TextStyle(fontSize: 11));
                              },
                            ),
                          ),
                          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                        ),
                        gridData: const FlGridData(show: true),
                        borderData: FlBorderData(show: true),
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}