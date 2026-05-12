# Backtesting Flutter App

This folder contains the Flutter frontend for the Efficient Frontier Portfolio Optimizer.

## Main Features

- Portfolio construction from a predefined stock universe.
- Efficient frontier simulation with max weight constraints.
- Optimized portfolio candidates: Max Sharpe, Min Volatility, and Max Sortino.
- Manual portfolio builder with custom weights.
- Firebase authentication and saved portfolio history.
- Out-of-sample backtesting against benchmarks or other saved portfolios.
- Correlation analysis and bootstrap-based future outcome simulation.

## App Screens

- `frontier_screen.dart`: stock selection, efficient frontier simulation, optimized portfolio saving, and manual portfolio creation.
- `performance_screen.dart`: saved portfolio backtesting, benchmark comparison, correlation, and forecast simulation.
- `saved_portfolios.dart`: saved portfolio history.
- `how_it_works_screen.dart`: in-app explanation of the workflow and financial methodology.
- `settings_screen.dart`: theme, password, and account management.

## Backend

The app communicates with a FastAPI backend in `lib/python/main.py`. The backend provides endpoints for:

- `/optimize`
- `/portfolio-stats`
- `/backtest`
- `/simulate`
- `/correlation`
- `/tickers`

The deployed frontend currently points to the hosted API at:

```text
https://efficientfrontier.onrender.com
```

## Run Locally

Install Flutter packages:

```bash
flutter pub get
```

Run the app:

```bash
flutter run
```

Run the backend:

```bash
cd lib/python
pip install -r requirements.txt
uvicorn main:app --reload
```

## Notes

The app is intended for portfolio analysis and academic demonstration. It does not account for all real-world trading frictions, including taxes, transaction costs, liquidity limits, or future market regime changes.
