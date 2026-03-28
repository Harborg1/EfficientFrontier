from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
import yfinance as yf
import pandas as pd
import numpy as np
from typing import List, Dict, Optional
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

# --- ENDPOINT 1: OPTIMIZE (Træning) ---
@app.get("/optimize")

def get_portfolio_data(
    tickers: str = "", 
    max_weight: float = 0.30,            
    start_date: str = "2015-01-01",      
    end_date: str = "2019-12-31", 
    num_portfolios: int = 20000        
):
    if not tickers:
        selected = ['AAPL', 'MSFT', 'GOOGL','TSLA', 'XOM','V' , 'JNJ', 'AMZN', 'WMT','ADBE']
    else:
        selected = list(set([t.strip().upper() for t in tickers.split(",") if t.strip()]))

    selected = selected[:15] 
    selected.sort()
    num_assets = len(selected)

    if num_assets * max_weight < 1.0:
        return {"error": f"Kan ikke summere til 100% med {num_assets} aktier og et max på {max_weight*100}%."}
    
    # Henter data for TRÆNINGS-perioden
    data = yf.download(selected, start=start_date, end=end_date, auto_adjust=False)
    if data.empty or 'Adj Close' not in data:
        return {"error": "Could not retrieve data for the specified tickers."}
    
    table = data['Adj Close'].dropna(axis=1, how='all').dropna()
    selected = list(table.columns) 
    num_assets = len(selected)
    
    returns_daily = table.pct_change().dropna()
    returns_annual = (returns_daily.mean() * 250).values 
    cov_annual = (returns_daily.cov() * 250).values

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
        return {"error": "Kravene var så stramme, at vi ikke kunne finde nogen lovlige porteføljer. Prøv at hæve max_weight."}

    valid_weights = np.vstack(valid_weights_list)[:num_portfolios]
    
    port_returns = np.dot(valid_weights, returns_annual)
    port_volatility = np.sqrt(np.sum(np.dot(valid_weights, cov_annual) * valid_weights, axis=1))

    portfolio = {'Returns': port_returns, 'Volatility': port_volatility}
    for counter, symbol in enumerate(selected):
        portfolio[symbol+' weight'] = valid_weights[:, counter]

    df = pd.DataFrame(portfolio)
    df['Sharpe'] = df['Returns'] / df['Volatility']

    best_sharpe_idx = df['Sharpe'].idxmax()
    max_sharpe_port = df.loc[best_sharpe_idx]

    least_var_idx = df['Volatility'].idxmin()
    min_vol_port = df.loc[least_var_idx]

    def extract_weights(port_series):
        return {symbol: round(float(port_series[symbol+' weight']), 4) for symbol in selected}

    return {
        "scatter_points": [{"x": float(v), "y": float(r)} for v, r in zip(df['Volatility'], df['Returns'])],
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
        }
    }

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
        valid_tickers = [t for t in data.tickers if t in returns.columns]
        
        w_array = np.array([data.weights[t] for t in valid_tickers])
        w_array /= w_array.sum()
        
        # --- ÆGTE BUY & HOLD MATEMATIK ---
        cum_returns_assets = (1 + returns[valid_tickers]).cumprod()
        port_cum_value = (cum_returns_assets * w_array).sum(axis=1)
        port_daily = (port_cum_value / port_cum_value.shift(1).fillna(1.0)) - 1.0
        
        benchmark_daily = returns[benchmark_ticker]

        def calculate_kpis(daily_rets):
            cum_rets = (1 + daily_rets).cumprod()
            total_return = (cum_rets.iloc[-1] - 1) * 100
            vol = daily_rets.std() * np.sqrt(252) * 100
            sharpe = (daily_rets.mean() / daily_rets.std()) * np.sqrt(252) if daily_rets.std() != 0 else 0
            
            peak = cum_rets.cummax()
            drawdown = (cum_rets - peak) / peak
            max_dd = drawdown.min() * 100
            
            return {
                "sharpe": round(float(sharpe), 2),
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
        valid_tickers = [t for t in data.tickers if t in returns.columns]
        
        w_array = np.array([data.weights[t] for t in valid_tickers])
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
    
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/tickers")
def get_available_tickers():
    return {"tickers": TICKER_UNIVERSE}

if __name__ == "__main__":
    port = int(os.environ.get("PORT", 8000))
    uvicorn.run(app, host="0.0.0.0", port=port)
