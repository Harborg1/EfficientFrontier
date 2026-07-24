# Repository Guidelines

## Project Structure & Module Organization

This repository contains the Efficient Frontier Portfolio Optimizer. The main app lives in `BackTesting/backtesting`, a Flutter project with Firebase integration and a Python FastAPI backend.

- `BackTesting/backtesting/lib/main.dart`: Flutter app entry point.
- `BackTesting/backtesting/lib/screens/`: user-facing screens such as portfolio optimization, saved portfolios, settings, and performance analysis.
- `BackTesting/backtesting/lib/theme/`: shared theme definitions and theme state.
- `BackTesting/backtesting/lib/python/`: FastAPI backend, optimizer logic, and `requirements.txt`.
- `BackTesting/backtesting/test/`: Flutter widget and unit tests.
- `android/`, `ios/`, `macos/`, `linux/`, `windows/`, and `web/`: generated or platform-specific Flutter project files. Edit these only when platform behavior requires it.

## Build, Test, and Development Commands

Run Flutter commands from `BackTesting/backtesting`:

```bash
flutter pub get
flutter analyze
flutter test
flutter run
flutter build web
```

- `flutter pub get` installs Dart dependencies from `pubspec.yaml`.
- `flutter analyze` runs the configured Flutter lints.
- `flutter test` runs tests under `test/`.
- `flutter run` starts the app locally.
- `flutter build web` produces a deployable web build.

Run the Python API from `BackTesting/backtesting/lib/python`:

```bash
pip install -r requirements.txt
uvicorn main:app --reload
```

## Coding Style & Naming Conventions

Use Dart conventions for Flutter code: 2-space indentation, `UpperCamelCase` for widgets/classes, `lowerCamelCase` for methods and variables, and `snake_case.dart` filenames. Keep screen-specific UI in `lib/screens/` and shared visual state in `lib/theme/`.

The project includes `flutter_lints` via `analysis_options.yaml`; resolve analyzer warnings before submitting changes. For Python, use 4-space indentation, `snake_case` functions, Pydantic request models named with `Request`, and clear endpoint helper functions.

## Testing Guidelines

Place Flutter tests in `test/` and name files with `_test.dart`. Add or update tests for new widgets, navigation behavior, and portfolio workflow changes. Backend changes should be checked with targeted local API requests against `uvicorn main:app --reload`, especially for `/optimize`, `/backtest`, `/simulate`, and `/correlation`.

## Commit & Pull Request Guidelines

Recent commits use short summaries such as `Update frontier_screen.dart` and `Fix error`. Keep commit subjects concise, imperative, and specific, for example `Add rolling backtest validation`.

Pull requests should include a short description, the main files or screens changed, test commands run, and screenshots for visible UI changes. Mention API or Firebase configuration changes explicitly.

## Security & Configuration Tips

Do not commit new secrets, service credentials, or local environment files. Treat `lib/firebase_options.dart` and platform Firebase config files as environment-sensitive, and document any required setup changes in the PR.
