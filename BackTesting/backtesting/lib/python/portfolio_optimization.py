from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
import yfinance as yf
import pandas as pd
import numpy as np

app = FastAPI()

# IMPORTANT: Allow Flutter Web to talk to this API
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"], # In production, replace with your Flutter app's URL
    allow_methods=["*"],
    allow_headers=["*"],
)

@app.get("/optimize")
def get_portfolio_data(tickers: str = "AAPL,F,WMT,GOOG,TSLA"):
    selected = tickers.split(",")
    # Fetch data
    data = yf.download(selected, start='2020-01-01', end='2025-12-31')
    table = data['Close']
    
    # Calculate returns and covariance
    returns_daily = table.pct_change().dropna()
    returns_annual = returns_daily.mean() * 252 # Using 252 trading days
    cov_annual = returns_daily.cov() * 252
    
    num_assets = len(selected)
    num_portfolios = 5000 
    
    results = np.zeros((3, num_portfolios))
    port_data = []

    for i in range(num_portfolios):
        weights = np.random.random(num_assets)
        weights /= np.sum(weights)
        
        portfolio_return = np.dot(weights, returns_annual)
        portfolio_volatility = np.sqrt(np.dot(weights.T, np.dot(cov_annual, weights)))
        
        results[0,i] = portfolio_return
        results[1,i] = portfolio_volatility
        results[2,i] = results[0,i] / results[1,i] # Sharpe Ratio (assuming 0% Risk-Free Rate)
        
        port_data.append({"x": float(portfolio_volatility), "y": float(portfolio_return)})

    # Find key indices
    max_sharpe_idx = np.argmax(results[2])
    min_vol_idx = np.argmin(results[1])

    return {
        "scatter_points": port_data,
        "min_vol": {
            "x": float(results[1, min_vol_idx]), 
            "y": float(results[0, min_vol_idx])
        },
        "max_sharpe": {
            "x": float(results[1, max_sharpe_idx]), 
            "y": float(results[0, max_sharpe_idx])
        }
    }