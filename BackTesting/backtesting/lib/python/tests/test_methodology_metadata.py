import unittest
from unittest.mock import patch

import numpy as np
import pandas as pd

import main as api


def _price_table() -> pd.DataFrame:
    """Return enough deterministic history for one rolling test window."""
    dates = pd.bdate_range("2019-01-01", "2021-01-01", inclusive="left")
    step = np.arange(len(dates), dtype=float)
    return pd.DataFrame(
        {
            "AAPL": 100.0 * np.exp(0.0004 * step) * (1.0 + 0.01 * np.sin(step / 9.0)),
            "MSFT": 90.0 * np.exp(0.0003 * step) * (1.0 + 0.008 * np.cos(step / 11.0)),
        },
        index=dates,
    )


def _optimization_result(weights=None):
    weights = weights or {"AAPL": 0.5, "MSFT": 0.5}

    def portfolio(annual_return: float, volatility: float):
        return {
            "x": volatility,
            "y": annual_return,
            "return": annual_return,
            "volatility": volatility,
            "weights": weights.copy(),
        }

    max_sharpe = portfolio(0.12, 0.18)
    max_sharpe["sharpe"] = 0.12 / 0.18
    max_sortino = portfolio(0.11, 0.17)
    max_sortino["sortino"] = 0.11 / 0.17

    return {
        "scatter_points": [],
        "max_sharpe": max_sharpe,
        "min_vol": portfolio(0.08, 0.12),
        "max_sortino": max_sortino,
    }


class OptimizeMethodologyTests(unittest.TestCase):
    def test_optimize_identifies_same_period_selection_and_evaluation(self):
        with (
            patch.object(api.yf, "download", return_value=object()),
            patch.object(api, "_adj_close_table", return_value=_price_table()),
            patch.object(api, "_optimize_from_returns", return_value=_optimization_result()),
        ):
            result = api.get_portfolio_data(
                tickers="AAPL,MSFT",
                max_weight=0.5,
                start_date="2019-01-01",
                end_date="2020-01-01",
                num_portfolios=100,
            )

        self.assertEqual(
            result["methodology"],
            {
                "evaluation_type": "ex_post_in_sample",
                "label": "Ex-post in-sample",
                "selection_start_date": "2019-01-01",
                "selection_end_date": "2020-01-01",
                "evaluation_start_date": "2019-01-01",
                "evaluation_end_date": "2020-01-01",
                "uses_same_period_for_selection_and_evaluation": True,
            },
        )


class RollingMethodologyTests(unittest.IsolatedAsyncioTestCase):
    async def test_rolling_backtest_identifies_walk_forward_evaluation(self):
        optimization_inputs = []
        optimization_results = iter(
            [
                _optimization_result(),
                _optimization_result({"AAPL": 0.6, "MSFT": 0.4}),
            ]
        )

        def optimize(returns_daily, *args, **kwargs):
            optimization_inputs.append(returns_daily.copy())
            return next(optimization_results)

        request = api.RollingBacktestRequest(
            tickers=["AAPL", "MSFT"],
            max_weight=0.6,
            backtest_start_date="2020-01-01",
            backtest_end_date="2021-01-01",
            lookback_years=1,
            rebalance_months=12,
            num_portfolios=100,
        )

        with (
            patch.object(api.yf, "download", return_value=object()),
            patch.object(api, "_adj_close_table", return_value=_price_table()),
            patch.object(api, "_optimize_from_returns", side_effect=optimize),
        ):
            result = await api.rolling_backtest(request)

        self.assertEqual(
            result["methodology"],
            {
                "evaluation_type": "rolling_walk_forward_out_of_sample",
                "label": "Rolling walk-forward out-of-sample",
                "strategy_start_date": "2020-01-01",
                "evaluation_start_date": "2020-01-01",
                "evaluation_end_date": "2021-01-01",
                "lookback_years": 1,
                "rebalance_months": 12,
                "reoptimized_each_window": True,
                "training_data_cutoff": "strictly_before_each_rebalance_date",
            },
        )
        self.assertEqual(len(result["runs"]), 1)
        self.assertEqual(result["runs"][0]["training_end_date"], "2020-01-01")
        self.assertEqual(result["runs"][0]["start_date"], "2020-01-01")
        self.assertEqual(result["report_start_date"], "2020-01-01")

        self.assertEqual(len(optimization_inputs), 2)
        self.assertLess(
            optimization_inputs[-1].index.max(),
            pd.Timestamp("2021-01-01"),
        )
        self.assertEqual(
            result["next_allocations"],
            {
                "as_of_date": "2021-01-01",
                "training_start_date": "2020-01-01",
                "training_end_date": "2021-01-01",
                "training_data_cutoff": "strictly_before_as_of_date",
                "portfolios": {
                    "max_sharpe": {
                        "weights": {"AAPL": 0.6, "MSFT": 0.4},
                        "training_return": 0.12,
                        "training_volatility": 0.18,
                        "training_sharpe": 0.12 / 0.18,
                    },
                    "min_vol": {
                        "weights": {"AAPL": 0.6, "MSFT": 0.4},
                        "training_return": 0.08,
                        "training_volatility": 0.12,
                    },
                    "max_sortino": {
                        "weights": {"AAPL": 0.6, "MSFT": 0.4},
                        "training_return": 0.11,
                        "training_volatility": 0.17,
                        "training_sortino": 0.11 / 0.17,
                    },
                },
            },
        )
        self.assertEqual(
            result["summary"]["max_sharpe"]["weights"],
            {"AAPL": 0.5, "MSFT": 0.5},
        )

    async def test_report_start_filters_summary_without_shifting_strategy_start(self):
        request = api.RollingBacktestRequest(
            tickers=["AAPL", "MSFT"],
            max_weight=0.5,
            backtest_start_date="2020-01-01",
            backtest_end_date="2021-01-01",
            report_start_date="2020-07-01",
            lookback_years=1,
            rebalance_months=6,
            num_portfolios=100,
        )

        with (
            patch.object(api.yf, "download", return_value=object()),
            patch.object(api, "_adj_close_table", return_value=_price_table()),
            patch.object(
                api,
                "_optimize_from_returns",
                side_effect=lambda *args, **kwargs: _optimization_result(),
            ),
        ):
            result = await api.rolling_backtest(request)

        expected_report_returns = api._window_returns(
            _price_table(),
            ["AAPL", "MSFT"],
            "2020-07-01",
            "2021-01-01",
        )

        self.assertEqual(result["runs"][0]["start_date"], "2020-01-01")
        self.assertEqual(result["runs"][1]["start_date"], "2020-07-01")
        self.assertEqual(result["report_start_date"], "2020-07-01")
        self.assertEqual(result["methodology"]["strategy_start_date"], "2020-01-01")
        self.assertEqual(result["methodology"]["evaluation_start_date"], "2020-07-01")
        self.assertEqual(
            len(result["summary"]["max_sharpe"]["equity_curve"]),
            len(expected_report_returns),
        )


if __name__ == "__main__":
    unittest.main()
