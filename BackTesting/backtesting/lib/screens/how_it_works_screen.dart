import 'package:flutter/material.dart';

class HowItWorksScreen extends StatelessWidget {
  const HowItWorksScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text("How the app works"),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "Portfolio Optimizer helps you build, test, and understand your portfolio.",
                    style: TextStyle(
                      fontSize: 18,
                      height: 1.5,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 24),
                  _InfoCard(
                    icon: Icons.tune_rounded,
                    title: "1. Choose stocks and build your portfolio",
                    body:
                        "In the portfolio optimization window, you choose your stocks. You can either let the app calculate the optimal weighting using the 'Efficient Frontier', or you can adjust the weights yourself with the manual portfolio builder.",
                  ),
                  const SizedBox(height: 16),
                  _InfoCard(
                    icon: Icons.bubble_chart_rounded,
                    title: "2. Optimization and saved portfolios",
                    body:
                        "During optimization, the app simulates thousands of allocations to find portfolios with, for example, high Sharpe or low volatility. You can easily save both optimized portfolios and your own manual portfolios directly to the cloud.",
                  ),
                  const SizedBox(height: 16),
                  _InfoCard(
                    icon: Icons.history_toggle_off_rounded,
                    title: "3. Performance and comparison",
                    body:
                        "Under 'Performance', you can run an out-of-sample backtest. Here, you can test your portfolio's return and risk, and compare it directly with standard benchmarks (SPY, QQQ, etc.) or your other saved portfolios.",
                  ),
                  const SizedBox(height: 24),
                  Text(
                    "How the periods are used",
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    """The time horizon on the portfolio optimization screen is used as the training window to find the weights that provide the best return. In "View Performance", you see an out-of-sample test using the same weights, so you can evaluate how the portfolio performs after the optimization.""",
                    style: TextStyle(
                      fontSize: 15,
                      height: 1.5,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    "What you see in the app",
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  const _BulletLine(text: "Efficient frontier with annual risk and annual return"),
                  const _BulletLine(text: "Max Sharpe ratio and Min Volatility portfolios"),
                  const _BulletLine(text: "Option to design and test your own manual portfolio"),
                  const _BulletLine(text: "Backtest and comparison with benchmarks or other portfolios"),
                  const _BulletLine(text: "Correlation for the selected portfolio"),
                  const _BulletLine(text: "Forecast/simulation for possible future outcomes"),
                  const SizedBox(height: 32),
                  SizedBox(
                    width: double.infinity,
                    height: 54,
                    child: FilledButton.icon(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.arrow_back_rounded),
                      label: const Text("Back"),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      elevation: 0,
      color: theme.colorScheme.surfaceVariant.withOpacity(0.35),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withOpacity(0.12),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, color: theme.colorScheme.primary),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    body,
                    style: TextStyle(
                      fontSize: 14,
                      height: 1.45,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BulletLine extends StatelessWidget {
  const _BulletLine({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 6, right: 10),
            child: Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(
                color: theme.colorScheme.primary,
                shape: BoxShape.circle,
              ),
            ),
          ),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 14,
                height: 1.45,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}