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

# 1. Define your expanded universe (S&P 100, Tech, etc.)
TICKER_UNIVERSE = [
    "AAPL", "MSFT", "GOOGL", "AMZN", "META", "TSLA", "NVDA", "BRK-B", "JPM", "V", 
    "JNJ", "WMT", "PG", "MA", "UNH", "HD", "DIS", "BAC", "VZ", "KO", "PFE", 
    "INTC", "CMCSA", "NFLX", "ADBE", "T", "ABT", "PEP", "XOM", "CSCO"
]

@app.get("/optimize")
def get_portfolio_data(tickers: str = ""):
    # 2. Use user input if provided, otherwise default to a diverse selection
    if not tickers:
        selected = ["AAPL", "MSFT", "GOOGL", "TSLA", "AMZN", "NFLX", "NVDA"]
    else:
        # Filter and validate input against the universe or just clean it
        selected = [t.strip().upper() for t in tickers.split(",") if t.strip() and t.strip().upper() in TICKER_UNIVERSE]

    # Limit to a reasonable number to prevent the free-tier server from timing out
    selected = selected[:15] 

    # Fetch data
    data = yf.download(selected, start='2021-01-01', end='2025-12-31')
    
    if data.empty or 'Close' not in data:
        return {"error": "Could not retrieve data for the specified tickers."}
        
    table = data['Close']
    
    # Calculate returns and covariance
    returns_daily = table.pct_change().dropna()
    returns_annual = returns_daily.mean() * 252 
    cov_annual = returns_daily.cov() * 252
    
    num_assets = len(selected)
    num_portfolios = 3000

    # Optimization: Using vectorized operations where possible
    weights_matrix = np.random.random((num_portfolios, num_assets))
    weights_matrix /= np.sum(weights_matrix, axis=1)[:, np.newaxis]
    
    port_returns = np.dot(weights_matrix, returns_annual)
    # Volatility calculation for all portfolios at once
    port_vols = np.sqrt(np.diag(np.dot(weights_matrix, np.dot(cov_annual, weights_matrix.T))))
    sharpe_ratios = port_returns / port_vols
    
    # Format scatter data for Flutter
    port_data = [{"x": float(v), "y": float(r)} for v, r in zip(port_vols, port_returns)]

    # Find key indices
    max_sharpe_idx = np.argmax(sharpe_ratios)
    min_vol_idx = np.argmin(port_vols)

    # Helper function to map weights
    def get_weight_dict(idx):
        return {selected[i]: round(float(weights_matrix[idx, i]), 4) for i in range(num_assets)}

    return {
        "scatter_points": port_data,
        "max_sharpe": {
            "x": float(port_vols[max_sharpe_idx]), 
            "y": float(port_returns[max_sharpe_idx]),
            "sharpe": float(sharpe_ratios[max_sharpe_idx]),
            "weights": get_weight_dict(max_sharpe_idx)
        },
        "min_vol": {
            "x": float(port_vols[min_vol_idx]), 
            "y": float(port_returns[min_vol_idx]),
            "weights": get_weight_dict(min_vol_idx)
        }
    }

# 3. New endpoint to give the Flutter app the list of available stocks
@app.get("/tickers")
def get_available_tickers():
    return {"tickers": TICKER_UNIVERSE}    