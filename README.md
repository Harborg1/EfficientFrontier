# Efficient Frontier Portfolio Optimizer

Efficient Frontier is a portfolio optimization and backtesting application built with Flutter, Firebase, and a Python FastAPI backend. The project lets users construct equity portfolios, generate efficient frontier simulations, save optimized or manual portfolios, and evaluate performance out of sample against market benchmarks.

Try the deployed app: https://efficient-frontier.vercel.app/

## What The App Does

- Builds portfolios from a selected stock universe.
- Simulates thousands of constrained portfolio allocations.
- Identifies Max Sharpe, Min Volatility, and Max Sortino portfolios.
- Supports custom manual portfolio weights.
- Saves portfolios to Firebase per authenticated user.
- Backtests saved portfolios on later market data.
- Compares portfolios against benchmarks such as SPY, QQQ, DIA, and IWM.
- Calculates performance metrics including return, volatility, Sharpe ratio, Sortino ratio, max drawdown, and correlation.
- Runs bootstrap-based simulations to estimate possible future outcome ranges.

## Project Structure

```text
EfficientFrontier/
├── README.md
└── BackTesting/
    └── backtesting/
        ├── lib/
        │   ├── main.dart
        │   ├── screens/
        │   │   ├── frontier_screen.dart
        │   │   ├── performance_screen.dart
        │   │   ├── saved_portfolios.dart
        │   │   └── how_it_works_screen.dart
        │   ├── theme/
        │   └── python/
        │       ├── main.py
        │       └── requirements.txt
        ├── pubspec.yaml
        └── firebase.json
```

## Methodology

The optimization screen uses historical adjusted close prices from Yahoo Finance through `yfinance`. Daily returns are annualized and combined with the annualized covariance matrix to estimate each simulated portfolio's expected return and risk.

Portfolio weights are sampled with a Dirichlet distribution, then filtered by the selected maximum weight constraint. From the valid portfolio set, the app highlights:

- Max Sharpe: highest return per unit of volatility.
- Min Volatility: lowest annualized risk.
- Max Sortino: highest return relative to downside volatility.

Saved portfolios can then be evaluated in a separate out-of-sample period. This helps separate the training period used for optimization from the later period used for performance testing.

## Technology

- Frontend: Flutter and Dart
- Charts: `fl_chart`
- Authentication and storage: Firebase Auth and Cloud Firestore
- Backend: FastAPI, Python, pandas, NumPy, yfinance
- Deployment: Vercel for the Flutter web app and Render for the API

## Local Development

Install Flutter dependencies:

```bash
cd BackTesting/backtesting
flutter pub get
```

Run the Flutter app:

```bash
flutter run
```

Run the Python API locally:

```bash
cd BackTesting/backtesting/lib/python
pip install -r requirements.txt
uvicorn main:app --reload
```

The deployed app currently calls the hosted API at `https://efficientfrontier.onrender.com`.

## Academic Focus

This project demonstrates a practical implementation of modern portfolio theory. It connects financial theory, simulation, persistent user workflows, and empirical performance evaluation in one working system.

The results should be interpreted as historical analysis rather than financial advice. Market data quality, selected time windows, transaction costs, taxes, survivorship bias, and future regime changes can all affect real-world performance.
