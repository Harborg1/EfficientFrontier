class PortfolioPoint {
  final double x; // Volatility
  final double y; // Return

  PortfolioPoint(this.x, this.y);
  
  factory PortfolioPoint.fromJson(Map<String, dynamic> json) {
    return PortfolioPoint(json['x'], json['y']);
  }
}