from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
import yfinance as yf
import pandas as pd
import numpy as np
from typing import List, Dict
import uvicorn
import os

app = FastAPI()

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

# --- KONFIGURATION OG MODELLER ---
TICKER_UNIVERSE = [
    "AAPL", "MSFT", "GOOGL", "AMZN", "META", "TSLA", "NVDA", "BRK-B", "JPM", "V",
    "JNJ", "WMT", "PG", "MA", "UNH", "HD", "DIS", "BAC", "VZ", "KO", "PFE",
    "INTC", "CMCSA", "NFLX", "ADBE", "T", "ABT", "PEP", "XOM", "CSCO"
]

class BacktestRequest(BaseModel):
    tickers: List[str]
    weights: Dict[str, float]
    test_start_date: str   # F.eks. "2020-01-01"
    test_end_date: str     # F.eks. "2025-12-31"
    benchmark: str = "SPY"

class SimulationRequest(BaseModel):
    tickers: List[str]
    weights: Dict[str, float]
    hist_start_date: str = "2019-01-01"
    hist_end_date: str = "2025-12-31"
    days_to_sim: int = 252
    simulations: int = 1000

class CorrelationRequest(BaseModel):
    tickers: List[str]
    weights: Dict[str, float]
    test_start_date: str
    test_end_date: str

class PortfolioStatsRequest(BaseModel):
    tickers: List[str]
    weights: Dict[str, float]
    start_date: str = "2020-01-01"
    end_date: str = "2025-12-31"

class RollingBacktestRequest(BaseModel):
    tickers: List[str]
    max_weight: float = 0.30
    backtest_start_date: str
    backtest_end_date: str
    lookback_years: int = 5
    rebalance_months: int = 6
    num_portfolios: int = 20000


OPTIMIZATION_TRADING_DAYS = 250
PERFORMANCE_TRADING_DAYS = 252
OBJECTIVE_KEYS = ("max_sharpe", "min_vol", "max_sortino")


def _selected_tickers_from_string(tickers: str) -> List[str]:
    if not tickers:
        selected = ['AAPL', 'MSFT', 'GOOGL','TSLA', 'XOM','V' , 'JNJ', 'AMZN', 'WMT','ADBE']
    else:
        selected = [t.strip().upper() for t in tickers.split(",") if t.strip()]

    selected = list(set(selected))[:15]
    selected.sort()
    return selected


def _selected_tickers_from_list(tickers: List[str]) -> List[str]:
    selected = list(set([t.strip().upper() for t in tickers if t.strip()]))[:15]
    selected.sort()
    return selected


def _adj_close_table(downloaded_data, selected: List[str]) -> pd.DataFrame:
    if downloaded_data.empty or 'Adj Close' not in downloaded_data:
        raise ValueError("Could not retrieve data for the specified tickers.")

    table = downloaded_data['Adj Close']
    if isinstance(table, pd.Series):
        table = table.to_frame(name=selected[0] if selected else "asset")

    return table.dropna(axis=1, how='all').dropna()


def _optimize_from_returns(
    returns_daily: pd.DataFrame,
    max_weight: float,
    num_portfolios: int,
    include_scatter: bool = True,
) -> Dict:
    returns_daily = returns_daily.dropna(axis=1, how='all').dropna()
    selected = list(returns_daily.columns)
    num_assets = len(selected)

    if num_assets == 0:
        raise ValueError("None of the selected tickers had enough valid return data.")
    if num_assets * max_weight < 1.0:
        raise ValueError(f"Kan ikke summere til 100% med {num_assets} aktier og et max på {max_weight*100}%.")

    returns_annual = (returns_daily.mean() * OPTIMIZATION_TRADING_DAYS).values
    cov_annual = (returns_daily.cov() * OPTIMIZATION_TRADING_DAYS).values

    valid_weights_list = []
    batch_size = 50000
    max_attempts = 100
    attempts = 0
    total_valid = 0

    while total_valid < num_portfolios and attempts < max_attempts:
        attempts += 1
        w_batch = np.random.dirichlet(np.ones(num_assets), size=batch_size)
        mask = np.all(w_batch <= max_weight, axis=1)
        valid_ones = w_batch[mask]

        if len(valid_ones) > 0:
            valid_weights_list.append(valid_ones)
            total_valid += len(valid_ones)

    if not valid_weights_list:
        raise ValueError("Kravene var så stramme, at vi ikke kunne finde nogen lovlige porteføljer. Prøv at hæve max_weight.")

    valid_weights = np.vstack(valid_weights_list)[:num_portfolios]

    port_returns = np.dot(valid_weights, returns_annual)
    port_volatility = np.sqrt(np.sum(np.dot(valid_weights, cov_annual) * valid_weights, axis=1))
    port_sortino = np.zeros(len(valid_weights))
    daily_return_values = returns_daily.values
    chunk_size = 5000

    for start in range(0, len(valid_weights), chunk_size):
        end = start + chunk_size
        chunk_daily = np.dot(daily_return_values, valid_weights[start:end].T)
        downside_std = np.where(chunk_daily < 0, chunk_daily, np.nan)
        downside_std = np.nanstd(downside_std, axis=0)
        chunk_mean = np.mean(chunk_daily, axis=0)
        port_sortino[start:end] = np.divide(
            chunk_mean * np.sqrt(OPTIMIZATION_TRADING_DAYS),
            downside_std,
            out=np.zeros_like(chunk_mean),
            where=(downside_std != 0) & ~np.isnan(downside_std)
        )

    portfolio = {'Returns': port_returns, 'Volatility': port_volatility, 'Sortino': port_sortino}
    for counter, symbol in enumerate(selected):
        portfolio[symbol+' weight'] = valid_weights[:, counter]

    df = pd.DataFrame(portfolio)
    df['Sharpe'] = np.divide(
        df['Returns'],
        df['Volatility'],
        out=np.zeros(len(df), dtype=float),
        where=df['Volatility'] != 0,
    )

    best_sharpe_idx = df['Sharpe'].idxmax()
    max_sharpe_port = df.loc[best_sharpe_idx]

    least_var_idx = df['Volatility'].idxmin()
    min_vol_port = df.loc[least_var_idx]

    best_sortino_idx = df['Sortino'].idxmax()
    max_sortino_port = df.loc[best_sortino_idx]

    def extract_weights(port_series):
        return {symbol: round(float(port_series[symbol+' weight']), 4) for symbol in selected}

    result = {
        "max_sharpe": {
            "x": float(max_sharpe_port['Volatility']),
            "y": float(max_sharpe_port['Returns']),
            "sharpe": float(max_sharpe_port['Sharpe']),
            "weights": extract_weights(max_sharpe_port)
        },
        "min_vol": {
            "x": float(min_vol_port['Volatility']),
            "y": float(min_vol_port['Returns']),
            "weights": extract_weights(min_vol_port)
        },
        "max_sortino": {
            "x": float(max_sortino_port['Volatility']),
            "y": float(max_sortino_port['Returns']),
            "sortino": float(max_sortino_port['Sortino']),
            "weights": extract_weights(max_sortino_port)
        }
    }

    if include_scatter:
        result["scatter_points"] = [{"x": float(v), "y": float(r)} for v, r in zip(df['Volatility'], df['Returns'])]

    return result


def _window_returns(price_table: pd.DataFrame, selected: List[str], start_date, end_date) -> pd.DataFrame:
    start_ts = pd.Timestamp(start_date)
    end_ts = pd.Timestamp(end_date)
    window_prices = price_table.loc[
        (price_table.index >= start_ts) & (price_table.index < end_ts),
        selected,
    ].dropna(axis=1, how='all').dropna()

    return window_prices.pct_change().dropna()


def _buy_hold_daily_returns(returns_daily: pd.DataFrame, weights: Dict[str, float]) -> pd.Series:
    valid_tickers = [ticker for ticker in weights.keys() if ticker in returns_daily.columns]
    if not valid_tickers:
        return pd.Series(dtype=float)

    w_array = np.array([weights[ticker] for ticker in valid_tickers], dtype=float)
    if w_array.sum() == 0:
        return pd.Series(dtype=float)
    w_array /= w_array.sum()

    window_returns = returns_daily[valid_tickers].dropna()
    if window_returns.empty:
        return pd.Series(dtype=float)

    cum_returns_assets = (1 + window_returns).cumprod()
    port_cum_value = (cum_returns_assets * w_array).sum(axis=1)
    return (port_cum_value / port_cum_value.shift(1).fillna(1.0)) - 1.0


def _performance_stats_from_daily(daily_rets: pd.Series) -> Dict[str, float]:
    daily_rets = pd.Series(daily_rets).dropna()
    if daily_rets.empty:
        return {
            "total_return": 0.0,
            "annualized_return": 0.0,
            "cagr": 0.0,
            "volatility": 0.0,
            "sharpe": 0.0,
            "sortino": 0.0,
            "max_drawdown": 0.0,
        }

    cum_rets = (1 + daily_rets).cumprod()
    total_return = float(cum_rets.iloc[-1] - 1)
    years = len(daily_rets) / PERFORMANCE_TRADING_DAYS
    cagr = float((cum_rets.iloc[-1] ** (1 / years)) - 1) if years > 0 else 0.0
    annualized_return = float(daily_rets.mean() * PERFORMANCE_TRADING_DAYS)
    daily_std = daily_rets.std()
    volatility = float(daily_std * np.sqrt(PERFORMANCE_TRADING_DAYS)) if not np.isnan(daily_std) else 0.0
    sharpe = float((daily_rets.mean() / daily_std) * np.sqrt(PERFORMANCE_TRADING_DAYS)) if daily_std != 0 and not np.isnan(daily_std) else 0.0
    downside_std = daily_rets[daily_rets < 0].std()
    sortino = float((daily_rets.mean() / downside_std) * np.sqrt(PERFORMANCE_TRADING_DAYS)) if downside_std != 0 and not np.isnan(downside_std) else 0.0

    peak = cum_rets.cummax()
    drawdown = (cum_rets - peak) / peak
    max_drawdown = float(drawdown.min())

    return {
        "total_return": total_return,
        "annualized_return": annualized_return,
        "cagr": cagr,
        "volatility": volatility,
        "sharpe": sharpe,
        "sortino": sortino,
        "max_drawdown": max_drawdown,
    }


def _date_label(value) -> str:
    return pd.Timestamp(value).strftime("%Y-%m-%d")


# --- ENDPOINT 5: Custom Portfolio Stats ---
@app.post("/portfolio-stats")
async def calculate_portfolio_stats(data: PortfolioStatsRequest):
    try:
        # Download data for the requested period
        df = yf.download(
            data.tickers,
            start=data.start_date,
            end=data.end_date,
            auto_adjust=False
        )['Adj Close']

        if df.empty:
            raise HTTPException(status_code=400, detail="Could not retrieve market data for the specified period")

        # Handle the case where yfinance returns a Series instead of a DataFrame (if only 1 ticker is queried)
        if isinstance(df, pd.Series):
            df = df.to_frame(name=data.tickers[0])

        returns = df.pct_change().dropna()
        valid_tickers = [t for t in data.tickers if t in returns.columns]

        if not valid_tickers:
            raise HTTPException(status_code=400, detail="None of the provided tickers had valid data.")

        # Normalize weights for the valid tickers
        w_array = np.array([data.weights.get(t, 0) for t in valid_tickers])
        if w_array.sum() == 0:
            raise HTTPException(status_code=400, detail="Total weight of valid tickers is 0.")
        w_array /= w_array.sum()

        # --- BUY & HOLD MATH (Consistent with your backtest endpoint) ---
        cum_returns_assets = (1 + returns[valid_tickers]).cumprod()
        port_cum_value = (cum_returns_assets * w_array).sum(axis=1)
        port_daily = (port_cum_value / port_cum_value.shift(1).fillna(1.0)) - 1.0

        # Calculate Annualized Return, Volatility and Sortino
        # Assuming 252 trading days in a year
        ann_return = port_daily.mean() * 252 * 100
        ann_volatility = port_daily.std() * np.sqrt(252) * 100
        downside_std = port_daily[port_daily < 0].std()
        sortino = (port_daily.mean() / downside_std) * np.sqrt(252) if downside_std != 0 and not np.isnan(downside_std) else 0

        # Calculate CAGR (Compound Annual Growth Rate) as an alternative metric
        years = len(port_daily) / 252
        cagr = ((port_cum_value.iloc[-1] / 1.0) ** (1 / years) - 1) * 100 if years > 0 else 0

        return {
            "period_start": data.start_date,
            "period_end": data.end_date,
            "valid_tickers": valid_tickers,
            "annualized_return_pct": round(float(ann_return), 2),
            "annualized_volatility_pct": round(float(ann_volatility), 2),
            "sortino_ratio": round(float(sortino), 2),
            "cagr_pct": round(float(cagr), 2)
        }

    except Exception as e:
        print(f"Error: {e}")
        raise HTTPException(status_code=500, detail=str(e))

# --- ENDPOINT 1: OPTIMIZE (Træning) ---
@app.get("/optimize")

def get_portfolio_data(
    tickers: str = "",
    max_weight: float = 0.30,
    start_date: str = "2015-01-01",
    end_date: str = "2019-12-31",
    num_portfolios: int = 20000
):
    selected = _selected_tickers_from_string(tickers)

    if len(selected) * max_weight < 1.0:
        return {"error": f"Kan ikke summere til 100% med {len(selected)} aktier og et max på {max_weight*100}%."}

    try:
        data = yf.download(selected, start=start_date, end=end_date, auto_adjust=False)
        table = _adj_close_table(data, selected)
        returns_daily = table.pct_change().dropna()
        return _optimize_from_returns(returns_daily, max_weight, num_portfolios)
    except ValueError as e:
        return {"error": str(e)}

@app.post("/rolling-backtest")
async def rolling_backtest(data: RollingBacktestRequest):
    try:
        if data.lookback_years <= 0:
            raise HTTPException(status_code=400, detail="lookback_years must be greater than 0.")
        if data.rebalance_months <= 0:
            raise HTTPException(status_code=400, detail="rebalance_months must be greater than 0.")

        selected = _selected_tickers_from_list(data.tickers)
        if not selected:
            raise HTTPException(status_code=400, detail="Please provide at least one ticker.")
        if len(selected) * data.max_weight < 1.0:
            raise HTTPException(
                status_code=400,
                detail=f"Kan ikke summere til 100% med {len(selected)} aktier og et max på {data.max_weight*100}%.",
            )

        backtest_start = pd.Timestamp(data.backtest_start_date)
        backtest_end = pd.Timestamp(data.backtest_end_date)
        if backtest_end <= backtest_start:
            raise HTTPException(status_code=400, detail="backtest_end_date must be after backtest_start_date.")

        download_start = backtest_start - pd.DateOffset(years=data.lookback_years)
        raw_data = yf.download(
            selected,
            start=_date_label(download_start),
            end=_date_label(backtest_end),
            auto_adjust=False,
        )
        price_table = _adj_close_table(raw_data, selected)
        valid_tickers = list(price_table.columns)

        if len(valid_tickers) * data.max_weight < 1.0:
            raise HTTPException(
                status_code=400,
                detail=f"Kan ikke summere til 100% med {len(valid_tickers)} aktier og et max på {data.max_weight*100}% efter datarensning.",
            )

        strategy_state = {
            key: {"latest_weights": {}, "daily_parts": []}
            for key in OBJECTIVE_KEYS
        }
        runs = []
        rebalance_date = backtest_start
        window_number = 1

        while rebalance_date < backtest_end:
            raw_application_end = rebalance_date + pd.DateOffset(months=data.rebalance_months)
            application_end = raw_application_end if raw_application_end < backtest_end else backtest_end
            if application_end <= rebalance_date:
                break

            training_start = rebalance_date - pd.DateOffset(years=data.lookback_years)
            training_returns = _window_returns(price_table, valid_tickers, training_start, rebalance_date)
            application_returns = _window_returns(price_table, valid_tickers, rebalance_date, application_end)

            if len(training_returns) < 30:
                raise HTTPException(
                    status_code=400,
                    detail=f"Not enough lookback data before {_date_label(rebalance_date)}. Try a shorter lookback or later backtest start date.",
                )

            if application_returns.empty:
                rebalance_date = application_end
                continue

            optimization = _optimize_from_returns(
                training_returns,
                data.max_weight,
                data.num_portfolios,
                include_scatter=False,
            )

            run = {
                "number": window_number,
                "training_start_date": _date_label(training_start),
                "training_end_date": _date_label(rebalance_date),
                "rebalance_date": _date_label(rebalance_date),
                "start_date": _date_label(rebalance_date),
                "end_date": _date_label(application_end),
            }

            for portfolio_key in OBJECTIVE_KEYS:
                state = strategy_state[portfolio_key]
                candidate_portfolio = optimization[portfolio_key]
                selected_weights = candidate_portfolio["weights"]
                application_daily = _buy_hold_daily_returns(application_returns, selected_weights)
                application_stats = _performance_stats_from_daily(application_daily)
                state["daily_parts"].append(application_daily)
                state["latest_weights"] = selected_weights

                run[portfolio_key] = {
                    "x": application_stats["volatility"],
                    "y": application_stats["annualized_return"],
                    "return": application_stats["annualized_return"],
                    "period_return": application_stats["total_return"],
                    "annualized_return": application_stats["annualized_return"],
                    "cagr": application_stats["cagr"],
                    "total_return": application_stats["total_return"],
                    "volatility": application_stats["volatility"],
                    "sharpe": application_stats["sharpe"],
                    "sortino": application_stats["sortino"],
                    "max_drawdown": application_stats["max_drawdown"],
                    "weights": selected_weights,
                    "rebalanced": True,
                    "training_return": candidate_portfolio["y"],
                    "training_volatility": candidate_portfolio["x"],
                }

            runs.append(run)
            rebalance_date = application_end
            window_number += 1

        if not runs:
            raise HTTPException(status_code=400, detail="No rebalance windows could be calculated for the selected dates.")

        summary = {}
        for portfolio_key in OBJECTIVE_KEYS:
            daily_parts = [
                part for part in strategy_state[portfolio_key]["daily_parts"]
                if part is not None and not part.empty
            ]
            if not daily_parts:
                continue

            full_daily = pd.concat(daily_parts).sort_index()
            stats = _performance_stats_from_daily(full_daily)
            equity_curve = (1 + full_daily).cumprod() * 100
            latest_weights = strategy_state[portfolio_key]["latest_weights"]

            summary[portfolio_key] = {
                "x": stats["volatility"],
                "y": stats["annualized_return"],
                "return": stats["annualized_return"],
                "annualized_return": stats["annualized_return"],
                "cagr": stats["cagr"],
                "total_return": stats["total_return"],
                "volatility": stats["volatility"],
                "sharpe": stats["sharpe"],
                "sortino": stats["sortino"],
                "max_drawdown": stats["max_drawdown"],
                "weights": latest_weights,
                "equity_curve": [
                    {"x": i, "y": round(float(value), 2)}
                    for i, value in enumerate(equity_curve)
                ],
            }

        return {
            "download_start_date": _date_label(download_start),
            "backtest_start_date": _date_label(backtest_start),
            "backtest_end_date": _date_label(backtest_end),
            "lookback_years": data.lookback_years,
            "rebalance_months": data.rebalance_months,
            "valid_tickers": valid_tickers,
            "runs": runs,
            "summary": summary,
        }

    except HTTPException:
        raise
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))
    except Exception as e:
        print(f"Rolling backtest error: {e}")
        raise HTTPException(status_code=500, detail=str(e))

# --- ENDPOINT 2: Backtest (Test / Out-of-Sample) ---
@app.post("/backtest")
async def backtest(data: BacktestRequest):
    try:
        benchmark_ticker = data.benchmark.upper()
        all_tickers = list(set(data.tickers + [benchmark_ticker]))

        # Henter KUN data for TEST-perioden (f.eks. 2020-2025)
        df = yf.download(
            all_tickers,
            start=data.test_start_date,
            end=data.test_end_date,
            auto_adjust=False
        )['Adj Close']

        if df.empty:
            raise HTTPException(status_code=400, detail="Could not retrieve market data for the test period")

        returns = df.pct_change().dropna()
        missing_weights = [t for t in data.tickers if t not in data.weights]
        if missing_weights:
            raise HTTPException(status_code=400, detail=f"Saved portfolio is missing weights for: {', '.join(missing_weights)}")

        valid_tickers = [t for t in data.tickers if t in returns.columns]
        if not valid_tickers:
            raise HTTPException(status_code=400, detail="No requested tickers had market data.")

        w_array = np.array([data.weights[t] for t in valid_tickers], dtype=float)
        if w_array.sum() == 0:
            raise HTTPException(status_code=400, detail="Total weight of valid tickers is 0.")
        w_array /= w_array.sum()

        # --- ÆGTE BUY & HOLD MATEMATIK ---
        cum_returns_assets = (1 + returns[valid_tickers]).cumprod()
        port_cum_value = (cum_returns_assets * w_array).sum(axis=1)
        port_daily = (port_cum_value / port_cum_value.shift(1).fillna(1.0)) - 1.0

        if benchmark_ticker not in returns.columns:
            raise HTTPException(status_code=400, detail=f"Benchmark {benchmark_ticker} had no market data in the test period.")
        benchmark_daily = returns[benchmark_ticker]

        def calculate_kpis(daily_rets):
            cum_rets = (1 + daily_rets).cumprod()
            total_return = (cum_rets.iloc[-1] - 1) * 100
            vol = daily_rets.std() * np.sqrt(252) * 100
            sharpe = (daily_rets.mean() / daily_rets.std()) * np.sqrt(252) if daily_rets.std() != 0 else 0
            downside_std = daily_rets[daily_rets < 0].std()
            sortino = (daily_rets.mean() / downside_std) * np.sqrt(252) if downside_std != 0 and not np.isnan(downside_std) else 0

            peak = cum_rets.cummax()
            drawdown = (cum_rets - peak) / peak
            max_dd = drawdown.min() * 100

            return {
                "sharpe": round(float(sharpe), 2),
                "sortino": round(float(sortino), 2),
                "volatility": round(float(vol), 2),
                "perf": round(float(total_return), 2),
                "max_drawdown": round(float(max_dd), 2)
            }

        return {
            "portfolio": [{"x": i, "y": round(val, 2)} for i, val in enumerate((1 + port_daily).cumprod() * 100)],
            "benchmark": [{"x": i, "y": round(val, 2)} for i, val in enumerate((1 + benchmark_daily).cumprod() * 100)],
            "portfolio_stats": calculate_kpis(port_daily),
            "benchmark_stats": calculate_kpis(benchmark_daily)
        }

    except HTTPException:
        raise
    except Exception as e:
        print(f"Error: {e}")
        raise HTTPException(status_code=500, detail=str(e))

# --- ENDPOINT 3: Simulate ---
@app.post("/simulate")
async def simulate_portfolio(data: SimulationRequest):
    try:
        # Henter historik for hele det valgte historiske vindue
        df = yf.download(
            data.tickers,
            start=data.hist_start_date,
            end=data.hist_end_date,
            auto_adjust=False
        )['Adj Close']

        if df.empty:
            raise HTTPException(status_code=400, detail="Kunne ikke hente historik til simulation")

        returns = df.pct_change().dropna()
        missing_weights = [t for t in data.tickers if t not in data.weights]
        if missing_weights:
            raise HTTPException(status_code=400, detail=f"Saved portfolio is missing weights for: {', '.join(missing_weights)}")

        valid_tickers = [t for t in data.tickers if t in returns.columns]
        if not valid_tickers:
            raise HTTPException(status_code=400, detail="No requested tickers had market data.")

        w_array = np.array([data.weights[t] for t in valid_tickers], dtype=float)
        if w_array.sum() == 0:
            raise HTTPException(status_code=400, detail="Total weight of valid tickers is 0.")
        w_array /= w_array.sum()

        # Genskab porteføljens sande historik (Buy & Hold metoden)
        cum_returns_assets = (1 + returns[valid_tickers]).cumprod()
        port_cum_value = (cum_returns_assets * w_array).sum(axis=1)
        port_daily_history = ((port_cum_value / port_cum_value.shift(1).fillna(1.0)) - 1.0).values

        # Block Bootstrapping
        block_size = 10
        num_blocks = (data.days_to_sim // block_size) + 1

        start_indices = np.random.randint(0, len(port_daily_history) - block_size, size=(num_blocks, data.simulations))

        sim_rets = np.zeros((num_blocks * block_size, data.simulations))
        for i in range(num_blocks):
            for j in range(block_size):
                sim_rets[i * block_size + j, :] = port_daily_history[start_indices[i, :] + j]

        sim_rets = sim_rets[:data.days_to_sim, :]

        paths = np.cumprod(1 + sim_rets, axis=0) * 100

        def prepare_path(p_values):
            return [100.0] + [round(float(v), 2) for v in p_values]

        forecast = {
            "p95": prepare_path(np.percentile(paths, 95, axis=1)),
            "p75": prepare_path(np.percentile(paths, 75, axis=1)),
            "median": prepare_path(np.percentile(paths, 50, axis=1)),
            "p25": prepare_path(np.percentile(paths, 25, axis=1)),
            "p5": prepare_path(np.percentile(paths, 5, axis=1)),
        }

        final_values = paths[-1]
        prob_loss = float(np.mean(final_values < 100) * 100)

        return {
            "days": list(range(data.days_to_sim + 1)),
            "forecast": forecast,
            "risk_metrics": {
                "prob_of_loss_percent": round(prob_loss, 2),
                "expected_final_value": round(float(np.mean(final_values)), 2),
                "worst_case_cvar_5pct": round(float(np.mean(final_values[final_values <= np.percentile(final_values, 5)])), 2)
            }
        }

    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.post("/correlation")
async def portfolio_correlation(data: CorrelationRequest):
    try:
        df = yf.download(
            data.tickers,
            start=data.test_start_date,
            end=data.test_end_date,
            auto_adjust=False
        )['Adj Close']

        if df.empty:
            raise HTTPException(status_code=400, detail="Kunne ikke hente historik til korrelation")

        returns = df.pct_change().dropna()
        missing_weights = [t for t in data.tickers if t not in data.weights]
        if missing_weights:
            raise HTTPException(status_code=400, detail=f"Saved portfolio is missing weights for: {', '.join(missing_weights)}")

        valid_tickers = [t for t in data.tickers if t in returns.columns]

        if len(valid_tickers) < 2:
            return {
                "portfolio_correlation": None,
                "valid_tickers": valid_tickers,
                "period_start": data.test_start_date,
                "period_end": data.test_end_date,
            }

        corr_matrix = returns[valid_tickers].corr().fillna(0.0)
        w_array = np.array([data.weights[t] for t in valid_tickers], dtype=float)
        if w_array.sum() == 0:
            raise HTTPException(status_code=400, detail="Total weight of valid tickers is 0.")
        w_array /= w_array.sum()

        weighted_corr_sum = 0.0
        pair_weight_sum = 0.0

        for i in range(len(valid_tickers)):
            for j in range(i + 1, len(valid_tickers)):
                pair_weight = float(w_array[i] * w_array[j])
                weighted_corr_sum += pair_weight * float(corr_matrix.iloc[i, j])
                pair_weight_sum += pair_weight

        portfolio_corr = weighted_corr_sum / pair_weight_sum if pair_weight_sum > 0 else None

        return {
            "portfolio_correlation": round(float(portfolio_corr), 3) if portfolio_corr is not None else None,
            "valid_tickers": valid_tickers,
            "period_start": data.test_start_date,
            "period_end": data.test_end_date,
        }

    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/tickers")
def get_available_tickers():
    return {"tickers": TICKER_UNIVERSE}

if __name__ == "__main__":
    port = int(os.environ.get("PORT", 8000))
    uvicorn.run(app, host="0.0.0.0", port=port)
