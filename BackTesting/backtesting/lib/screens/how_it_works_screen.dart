import 'package:flutter/material.dart';

class HowItWorksScreen extends StatelessWidget {
  const HowItWorksScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text("Sådan virker appen"),
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
                    "Portfolio Optimizer hjælper dig med at bygge, teste og forstå din portefølje.",
                    style: TextStyle(
                      fontSize: 18,
                      height: 1.5,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 24),
                  _InfoCard(
                    icon: Icons.tune_rounded,
                    title: "1. Vælg aktier og byg din portefølje",
                    body:
                        "I porteføljeoptimeringsvinduet vælger du dine aktier. Du kan enten lade appen beregne den optimale vægtning via 'Efficient Frontier', eller du kan justere vægtene selv med den manuelle porteføljebygger.",
                  ),
                  const SizedBox(height: 16),
                  _InfoCard(
                    icon: Icons.bubble_chart_rounded,
                    title: "2. Optimering og gemte porteføljer",
                    body:
                        "Ved optimering simulerer appen tusindvis af fordelinger for at finde porteføljer med f.eks. høj Sharpe eller lav volatilitet. Du kan nemt gemme både optimerede og dine egne manuelle porteføljer direkte i skyen.",
                  ),
                  const SizedBox(height: 16),
                  _InfoCard(
                    icon: Icons.history_toggle_off_rounded,
                    title: "3. Performance og sammenligning",
                    body:
                        "Under 'Performance' kan du lave en out-of-sample backtest. Her kan du teste dine porteføljers afkast og risiko, og du kan sammenligne dem direkte med standard benchmarks (SPY, QQQ m.m.) eller dine andre gemte porteføljer.",
                  ),
                  const SizedBox(height: 24),
                  Text(
                    "Sådan bruges perioderne",
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    """Tidshorisonten på porteføljeoptimerings skærmen bruges som træningsvinduet for at finde de vægte der giver det bedste afkast. I "Vis performance" ses en out-of-sample test med de samme vægte, så du kan vurdere, hvordan porteføljen klarer sig efter optimeringen.""",
                    style: TextStyle(
                      fontSize: 15,
                      height: 1.5,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    "Hvad du ser i appen",
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  const _BulletLine(text: "Efficient frontier med årlig risiko og årlig afkast"),
                  const _BulletLine(text: "Max Sharpe ratio- og Min Volatilitet-porteføljer"),
                  const _BulletLine(text: "Mulighed for at designe og teste din egen manuelle portefølje"),
                  const _BulletLine(text: "Backtest og sammenligning med benchmarks eller andre porteføljer"),
                  const _BulletLine(text: "Korrelation for den valgte portefølje"),
                  const _BulletLine(text: "Prognose/simulation for mulige fremtidige udfald"),
                  const SizedBox(height: 32),
                  SizedBox(
                    width: double.infinity,
                    height: 54,
                    child: FilledButton.icon(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.arrow_back_rounded),
                      label: const Text("Tilbage"),
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