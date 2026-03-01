from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
import yfinance as yf
import pandas as pd
import numpy as np
import scipy.optimize as sco # <-- New Import
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
    if not tickers:
        selected = ["AAPL", "MSFT", "GOOGL", "TSLA", "AMZN", "NFLX", "NVDA"]
    else:
        selected = [t.strip().upper() for t in tickers.split(",") if t.strip() and t.strip().upper() in TICKER_UNIVERSE]

    selected = selected[:15] 

    # Fetch data
    data = yf.download(selected, start='2021-01-01', end='2025-12-31')
    
    if data.empty or 'Close' not in data:
        return {"error": "Could not retrieve data for the specified tickers."}
        
    table = data['Close'].dropna()
    
    # Calculate returns and covariance
    returns_daily = table.pct_change().dropna()
    returns_annual = returns_daily.mean() * 252 
    cov_annual = returns_daily.cov() * 252
    
    num_assets = len(selected)

    # --- 2. SCIPY MATHEMATICAL OPTIMIZATION ---
    def portfolio_performance(weights, returns, cov):
        p_ret = np.sum(returns * weights)
        p_vol = np.sqrt(np.dot(weights.T, np.dot(cov, weights)))
        return p_ret, p_vol

    # Objective function: We want to Maximize Sharpe, so we Minimize the Negative Sharpe
    def neg_sharpe(weights, returns, cov):
        p_ret, p_vol = portfolio_performance(weights, returns, cov)
        return -p_ret / p_vol 

    # Objective function: Minimize Volatility
    def minimize_vol(weights, returns, cov):
        p_ret, p_vol = portfolio_performance(weights, returns, cov)
        return p_vol

    # Constraints: All weights must sum exactly to 1 (100% of capital)
    constraints = ({'type': 'eq', 'fun': lambda x: np.sum(x) - 1})
    
    # Bounds: Set a maximum limit per stock to enforce real diversification
    MAX_WEIGHT = 0.30 # No single stock can exceed 30% of the portfolio
    bounds = tuple((0.0, MAX_WEIGHT) for _ in range(num_assets))
    
    # Starting guess for the solver (equal weight distribution)
    init_guess = num_assets * [1. / num_assets]

    # Run the solver for Max Sharpe
    opt_sharpe = sco.minimize(neg_sharpe, init_guess, args=(returns_annual, cov_annual),
                              method='SLSQP', bounds=bounds, constraints=constraints)
    
    # Run the solver for Min Volatility
    opt_vol = sco.minimize(minimize_vol, init_guess, args=(returns_annual, cov_annual),
                           method='SLSQP', bounds=bounds, constraints=constraints)

    # Extract the exact optimal weights and performance metrics
    max_sharpe_weights = opt_sharpe.x
    max_sharpe_ret, max_sharpe_vol = portfolio_performance(max_sharpe_weights, returns_annual, cov_annual)
    max_sharpe_ratio = max_sharpe_ret / max_sharpe_vol

    min_vol_weights = opt_vol.x
    min_vol_ret, min_vol_vol = portfolio_performance(min_vol_weights, returns_annual, cov_annual)

    num_portfolios = 5000
    weights_matrix = np.random.random((num_portfolios, num_assets))
    weights_matrix /= np.sum(weights_matrix, axis=1)[:, np.newaxis]
    
    port_returns = np.dot(weights_matrix, returns_annual)
    # Using the fast memory-efficient calculation we discussed
    port_vols = np.sqrt(np.sum(weights_matrix * (weights_matrix @ cov_annual.values), axis=1))
    
    port_data = [{"x": float(v), "y": float(r)} for v, r in zip(port_vols, port_returns)]

    # Helper function to map weights
    def get_weight_dict(weights_array):
        # We use round to clean up floating point math (e.g. 0.2999999 -> 0.30)
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