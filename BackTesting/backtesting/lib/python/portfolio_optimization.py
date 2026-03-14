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
    returns_annual = returns_daily.mean() * 250
    cov_daily = returns_daily.cov()
    cov_annual = cov_daily * 250

    port_returns = []
    port_volatility = []
    stock_weights = []

    for single_portfolio in range(num_portfolios):
        weights = np.random.random(num_assets)
        weights /= np.sum(weights)
        returns = np.dot(weights, returns_annual)
        volatility = np.sqrt(np.dot(weights.T, np.dot(cov_annual, weights)))
        
        port_returns.append(returns)
        port_volatility.append(volatility)
        stock_weights.append(weights)

    portfolio = {'Returns': port_returns, 'Volatility': port_volatility}
    for counter, symbol in enumerate(selected):
        portfolio[symbol+' weight'] = [weight[counter] for weight in stock_weights]

    df = pd.DataFrame(portfolio)
    
    df['Sharpe'] = df['Returns'] / df['Volatility']

    weight_cols = [s + ' weight' for s in selected]
    df = df[df[weight_cols].max(axis=1) <= max_weight]
    
    if df.empty:
        return {"error": f"None of the {num_portfolios} portfolios met the max_weight constraint of {max_weight}."}
    if len(df) < 10:
        return {"error": "Not enough valid portfolios to calculate meaningful quantiles. Increase num_portfolios or max_weight."}

    # --- UPDATED: Subset Extraction Logic ---

    best_sharpe_idx = df['Sharpe'].idxmax()
    max_sharpe_port = df.loc[best_sharpe_idx]

    # 2. Absolute Minimum Volatility (Risk)
    least_var_idx = df['Volatility'].idxmin()
    min_vol_port = df.loc[least_var_idx]

    # ----------------------------------------

    port_data = [{"x": float(v), "y": float(r)} for v, r in zip(df['Volatility'], df['Returns'])]

    def extract_weights(port_series):
        return {symbol: round(float(port_series[symbol+' weight']), 4) for symbol in selected}

    return {
        "scatter_points": port_data,
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

@app.get("/tickers")
def get_available_tickers():
    return {"tickers": TICKER_UNIVERSE}