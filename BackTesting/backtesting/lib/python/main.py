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
    timeframe: str = "1y"
    benchmark: str = "SPY"  # <--- Added this field

    
# --- ENDPOINT 1: OPTIMIZE

@app.get("/optimize")
def get_portfolio_data(
    tickers: str = "", 
    max_weight: float = 0.30,            
    start_date: str = "2019-01-01",      
    end_date: str = "2025-12-31",        
    num_portfolios: int = 100000          
):
    if not tickers:
        selected = ["AAPL", "MSFT", "GOOGL", "TSLA", "AMZN", "NFLX", "NVDA"]
    else:
        selected = [t.strip().upper() for t in tickers.split(",") if t.strip() and t.strip().upper() in TICKER_UNIVERSE]

    selected = selected[:15] 
    selected.sort()
    num_assets = len(selected)

    if num_assets * max_weight < 1.0:
        return {"error": f"Cannot sum to 100% with {num_assets} assets capped at {max_weight*100}%. Increase the max weight."}
    
    data = yf.download(selected, start=start_date, end=end_date, auto_adjust=False)
    if data.empty or 'Adj Close' not in data:
        return {"error": "Could not retrieve data for the specified tickers."}
        
    table = data['Adj Close'].dropna()
    returns_daily = table.pct_change().dropna()
    
    # Vi bruger .values her for at gøre NumPy matrix-beregninger lynhurtige
    returns_annual = (returns_daily.mean() * 252).values 
    cov_annual = (returns_daily.cov() * 252).values

    # --- 1. GENERER ALLE TILFÆLDIGE VÆGTE PÅ ÉN GANG ---
    # Vi laver en matrix med 100.000 rækker og f.eks. 15 kolonner (aktier)
    all_weights = np.random.rand(num_portfolios, num_assets)
    
    # --- 2. NORMALISER ---
    # Vi dividerer hver række med sin egen sum, så alle rækker summerer til 1.0 (100%)
    all_weights = all_weights / all_weights.sum(axis=1, keepdims=True)
    
    # --- 3. FILTRER ---
    # Vi finder de rækker, hvor ALLE vægte er mindre end eller lig med max_weight
    valid_mask = np.all(all_weights <= max_weight, axis=1)
    valid_weights = all_weights[valid_mask]
    
    # Tjek om vi smed dem alle sammen ud
    if len(valid_weights) == 0:
        return {"error": f"Ud af {num_portfolios} simuleringer var der ingen, der ramte under max-vægten på {max_weight*100}%. Prøv flere simuleringer."}

    # --- 4. BEREGN PERFORMANCE FOR DE GODKENDTE ---
    # Matrix-multiplikation giver os afkast og risiko for alle overlevende porteføljer på én gang
    port_returns = np.dot(valid_weights, returns_annual)
    # Dette er den hurtige matrix-måde at skrive w * Cov * w.T for mange rækker
    port_volatility = np.sqrt(np.sum(np.dot(valid_weights, cov_annual) * valid_weights, axis=1))

    # --- 5. OPBYG DATAFRAME ---
    portfolio = {'Returns': port_returns, 'Volatility': port_volatility}
    for counter, symbol in enumerate(selected):
        portfolio[symbol+' weight'] = valid_weights[:, counter]

    df = pd.DataFrame(portfolio)
    df['Sharpe'] = df['Returns'] / df['Volatility']

    # Find vinderne
    best_sharpe_idx = df['Sharpe'].idxmax()
    max_sharpe_port = df.loc[best_sharpe_idx]

    least_var_idx = df['Volatility'].idxmin()
    min_vol_port = df.loc[least_var_idx]

    def extract_weights(port_series):
        return {symbol: round(float(port_series[symbol+' weight']), 4) for symbol in selected}

    # Returner data
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
# --- ENDPOINT 2: Backtest

@app.post("/backtest")
async def backtest(data: BacktestRequest):
    try:
        # Use the requested benchmark instead of hardcoded 'SPY'
        benchmark_ticker = data.benchmark.upper()
        all_tickers = list(set(data.tickers + [benchmark_ticker]))
        
        # Fetch historical data
        df = yf.download(all_tickers, period=data.timeframe, auto_adjust=False)['Adj Close']
        
        if df.empty:
            raise HTTPException(status_code=400, detail="Could not retrieve market data")

        returns = df.pct_change().dropna()
        valid_tickers = [t for t in data.tickers if t in returns.columns]
        
        # Calculate weights
        w_array = np.array([data.weights[t] for t in valid_tickers])
        w_array /= w_array.sum()
        
        # Calculate daily returns for Portfolio and the selected Benchmark
        port_daily = returns[valid_tickers].dot(w_array)
        benchmark_daily = returns[benchmark_ticker] # <--- Dynamic ticker index

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
            # We return this under the key 'benchmark' so the Flutter app knows where to look
            "benchmark": [{"x": i, "y": round(val, 2)} for i, val in enumerate((1 + benchmark_daily).cumprod() * 100)],
            "portfolio_stats": calculate_kpis(port_daily),
            "benchmark_stats": calculate_kpis(benchmark_daily)
        }
    
    except Exception as e:
        print(f"Error: {e}")
        raise HTTPException(status_code=500, detail=str(e))
    
@app.get("/tickers")
def get_available_tickers():
    return {"tickers": TICKER_UNIVERSE}

if __name__ == "__main__":

    port = int(os.environ.get("PORT", 8000))
    
    uvicorn.run(app, host="0.0.0.0", port=port)
