from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
import yfinance as yf
import pandas as pd
import numpy as np
from typing import List

app = FastAPI()

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

TICKER_UNIVERSE = [
    "AAPL", "MSFT", "GOOGL", "AMZN", "META", "TSLA", "NVDA", "BRK-B", "JPM", "V", 
    "JNJ", "WMT", "PG", "MA", "UNH", "HD", "DIS", "BAC", "VZ", "KO", "PFE", 
    "INTC", "CMCSA", "NFLX", "ADBE", "T", "ABT", "PEP", "XOM", "CSCO"
]

@app.get("/optimize")
def get_portfolio_data(
    tickers: str = "", 
    max_weight: float = 0.30,            
    start_date: str = "2019-01-01",      
    end_date: str = "2025-12-31",        
    num_portfolios: int = 5000           
):

    if not tickers:
        selected = ["AAPL", "MSFT", "GOOGL", "TSLA", "AMZN", "NFLX", "NVDA"]
    else:
        selected = [t.strip().upper() for t in tickers.split(",") if t.strip() and t.strip().upper() in TICKER_UNIVERSE]

    selected = selected[:15] 
    selected.sort()
    
    num_assets = len(selected)

    if num_assets * max_weight < 1.0:
        return {"error": f"Cannot sum to 100% with {num_assets} assets capped at {max_weight*100}%. Increase the max weight or add more tickers."}
        
    data = yf.download(selected, start=start_date, end=end_date, auto_adjust=False)
    
    if data.empty or 'Adj Close' not in data:
        return {"error": "Could not retrieve data for the specified tickers."}
        
    table = data['Adj Close'].dropna()
    
    returns_daily = table.pct_change().dropna()
    returns_annual = returns_daily.mean() * 252 
    cov_annual = returns_daily.cov() * 252

    # --- Generate random portfolios ---
    weights_matrix = np.random.random((num_portfolios, num_assets))
    weights_matrix /= np.sum(weights_matrix, axis=1)[:, np.newaxis]
    
    # Enforce max_weight constraint on random portfolios 
    valid_indices = np.all(weights_matrix <= max_weight, axis=1)
    valid_weights = weights_matrix[valid_indices]

    if len(valid_weights) < 10:
        return {"error": f"Only {len(valid_weights)} valid portfolios survived the max_weight constraint. Try increasing max_weight or generating more portfolios."}

    # Calculate returns, volatility, and Sharpe ratios
    port_returns = np.dot(valid_weights, returns_annual)
    port_vols = np.sqrt(np.sum(valid_weights * (valid_weights @ cov_annual.values), axis=1))
    port_sharpes = port_returns / port_vols
    
    # --- SUBSET SELECTION LOGIC ---
    
    # 1. Maximize Sharpe for the least amount of variance
    # Get the top 10% of portfolios by Sharpe Ratio
    sharpe_threshold = np.percentile(port_sharpes, 90)
    top_sharpe_indices = np.where(port_sharpes >= sharpe_threshold)[0]
    # Among those high-Sharpe portfolios, find the index of the one with the lowest volatility
    best_sharpe_least_var_idx = top_sharpe_indices[np.argmin(port_vols[top_sharpe_indices])]
    
    max_sharpe_weights = valid_weights[best_sharpe_least_var_idx]
    max_sharpe_ret = port_returns[best_sharpe_least_var_idx]
    max_sharpe_vol = port_vols[best_sharpe_least_var_idx]
    max_sharpe_ratio = port_sharpes[best_sharpe_least_var_idx]

    # 2. Minimize Variance for the best Sharpe
    # Get the bottom 10% of portfolios by volatility
    vol_threshold = np.percentile(port_vols, 10)
    lowest_vol_indices = np.where(port_vols <= vol_threshold)[0]
    # Among those low-volatility portfolios, find the index of the one with the highest Sharpe Ratio
    best_var_max_sharpe_idx = lowest_vol_indices[np.argmax(port_sharpes[lowest_vol_indices])]

    min_vol_weights = valid_weights[best_var_max_sharpe_idx]
    min_vol_ret = port_returns[best_var_max_sharpe_idx]
    min_vol_vol = port_vols[best_var_max_sharpe_idx]

    # Format scatter plot data
    port_data = [{"x": float(v), "y": float(r)} for v, r in zip(port_vols, port_returns)]

    def get_weight_dict(weights_array):
        return {selected[i]: round(float(weights_array[i]), 4) for i in range(num_assets)}

    return {
        "scatter_points": port_data,
        "max_sharpe": {
            "x": float(max_sharpe_vol), 
            "y": float(max_sharpe_ret),
            "sharpe": float(max_sharpe_ratio),
            "weights": get_weight_dict(max_sharpe_weights)
        },
        "min_vol": {
            "x": float(min_vol_vol), 
            "y": float(min_vol_ret),
            "weights": get_weight_dict(min_vol_weights)
        }
    }

@app.get("/tickers")
def get_available_tickers():
    return {"tickers": TICKER_UNIVERSE}