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
              constraints: const BoxConstraints(maxWidth: 820),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "Portfolio Optimizer combines modern portfolio theory with practical backtesting. You can create portfolios, optimize weights, save strategies, and test how they perform after the optimization period.",
                    style: TextStyle(
                      fontSize: 18,
                      height: 1.5,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 24),
                  _InfoCard(
                    icon: Icons.format_list_bulleted_rounded,
                    title: "1. Select stocks and constraints",
                    body:
                        "Start by choosing the stocks you want in the portfolio. You can also set the maximum allowed weight for each stock and decide how many portfolio allocations the app should simulate.",
                  ),
                  const SizedBox(height: 16),
                  _InfoCard(
                    icon: Icons.bubble_chart_rounded,
                    title: "2. Generate the efficient frontier",
                    body:
                        "The backend downloads historical prices, calculates daily returns and covariance, then simulates many valid weight combinations. The chart plots annualized volatility on the x-axis and annualized return on the y-axis.",
                  ),
                  const SizedBox(height: 16),
                  _InfoCard(
                    icon: Icons.workspace_premium_rounded,
                    title: "3. Identify optimized portfolios",
                    body:
                        "From the simulated portfolios, the app highlights three candidates: Max Sharpe for return per unit of volatility, Min Volatility for the lowest risk, and Max Sortino for return relative to downside risk.",
                  ),
                  const SizedBox(height: 16),
                  _InfoCard(
                    icon: Icons.edit_note_rounded,
                    title: "4. Build manual alternatives",
                    body:
                        "You can also create a manual portfolio by assigning your own weights. This makes it possible to compare an optimized strategy with a portfolio based on your own investment view.",
                  ),
                  const SizedBox(height: 16),
                  _InfoCard(
                    icon: Icons.query_stats_rounded,
                    title: "5. Backtest and compare",
                    body:
                        "Saved portfolios can be tested out of sample in the Performance screen. You can compare them with benchmarks such as SPY and QQQ, or compare two saved portfolios directly.",
                  ),
                  const SizedBox(height: 28),
                  _SectionTitle(title: "Training vs. Testing", theme: theme),
                  const SizedBox(height: 10),
                  Text(
                    "The optimization period is the training window. It is used to estimate returns, risk, and portfolio weights. The performance screen then evaluates the saved weights after the training period, which gives a more realistic out-of-sample test.",
                    style: TextStyle(
                      fontSize: 15,
                      height: 1.5,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 28),
                  _SectionTitle(title: "Metrics Used", theme: theme),
                  const SizedBox(height: 12),
                  const _BulletLine(
                    text:
                        "Annualized return estimates the portfolio's average yearly return from historical daily returns.",
                  ),
                  const _BulletLine(
                    text:
                        "Annualized volatility measures total return variation and is used as the main risk measure.",
                  ),
                  const _BulletLine(
                    text:
                        "Sharpe ratio compares return with total volatility. Higher values indicate more return per unit of risk.",
                  ),
                  const _BulletLine(
                    text:
                        "Sortino ratio focuses on downside volatility, so it penalizes harmful variation more directly.",
                  ),
                  const _BulletLine(
                    text:
                        "Maximum drawdown shows the largest peak-to-trough decline during the backtest period.",
                  ),
                  const _BulletLine(
                    text:
                        "Correlation estimates how closely the selected portfolio holdings move together.",
                  ),
                  const SizedBox(height: 28),
                  _SectionTitle(title: "What To Remember", theme: theme),
                  const SizedBox(height: 12),
                  const _BulletLine(
                    text:
                        "The app uses historical market data, so the results describe the past rather than guarantee the future.",
                  ),
                  const _BulletLine(
                    text:
                        "Optimization is sensitive to the selected stocks, period length, and maximum weight constraint.",
                  ),
                  const _BulletLine(
                    text:
                        "Backtesting improves evaluation, but it still does not include all real-world frictions such as taxes, trading costs, and liquidity limits.",
                  ),
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
      color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.45),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withOpacity(0.12),
                borderRadius: BorderRadius.circular(8),
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

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({
    required this.title,
    required this.theme,
  });

  final String title;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: theme.textTheme.titleLarge?.copyWith(
        fontWeight: FontWeight.bold,
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
