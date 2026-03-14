from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
import yfinance as yf
import pandas as pd
import numpy as np
from typing import List, Dict, Optional

app = FastAPI()

# Gør det muligt for din Flutter web-app at kalde din API
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

# --- ENDPOINT 1: OPTIMERING (Monte Carlo Simulation) ---

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
    cov_annual = returns_daily.cov() * 250

    port_returns = []
    port_volatility = []
    stock_weights = []

    # Simulation
    for _ in range(num_portfolios):
        weights = np.random.random(num_assets)
        weights /= np.sum(weights)
        
        # Tjek max weight constraint med det samme for hastighed
        if np.any(weights > max_weight):
            continue
            
        returns = np.dot(weights, returns_annual)
        volatility = np.sqrt(np.dot(weights.T, np.dot(cov_annual, weights)))
        
        port_returns.append(returns)
        port_volatility.append(volatility)
        stock_weights.append(weights)

    if not port_returns:
         return {"error": f"None of the portfolios met the max_weight constraint."}

    df = pd.DataFrame({'Returns': port_returns, 'Volatility': port_volatility})
    df['Sharpe'] = df['Returns'] / df['Volatility']

    # Find Max Sharpe og Min Vol
    best_sharpe_idx = df['Sharpe'].idxmax()
    least_var_idx = df['Volatility'].idxmin()

    def extract_weights(idx):
        return {symbol: round(float(stock_weights[idx][i]), 4) for i, symbol in enumerate(selected)}

    return {
        "scatter_points": [{"x": float(v), "y": float(r)} for v, r in zip(df['Volatility'], df['Returns'])][::10], # Subset for performance
        "max_sharpe": {
            "x": float(df.loc[best_sharpe_idx, 'Volatility']), 
            "y": float(df.loc[best_sharpe_idx, 'Returns']),
            "sharpe": float(df.loc[best_sharpe_idx, 'Sharpe']),
            "weights": extract_weights(best_sharpe_idx)
        },
        "min_vol": {
            "x": float(df.loc[least_var_idx, 'Volatility']), 
            "y": float(df.loc[least_var_idx, 'Returns']),
            "weights": extract_weights(least_var_idx)
        }
    }

# --- ENDPOINT 2: BACKTEST (Historisk sammenligning) ---

@app.post("/backtest")
async def backtest(data: BacktestRequest):
    try:
        # Hent portefølje-aktier + SPY som benchmark
        all_tickers = data.tickers + ['SPY']
        df = yf.download(all_tickers, period=data.timeframe)['Adj Close']
        
        if df.empty:
            raise HTTPException(status_code=400, detail="Could not fetch market data")

        # Beregn daglige afkast
        returns = df.pct_change().dropna()
        
        # Beregn vægtet porteføljeafkast pr. dag
        # Vi sikrer os at vi kun bruger tickers der faktisk kom med i downloadet
        valid_tickers = [t for t in data.tickers if t in returns.columns]
        port_returns = sum(returns[t] * data.weights[t] for t in valid_tickers)
        
        # Equity Curve (Startværdi 100)
        port_equity = ((1 + port_returns).cumprod() * 100).tolist()
        spy_equity = ((1 + returns['SPY']).cumprod() * 100).tolist()
        
        return {
            'portfolio': [{'x': i, 'y': round(val, 2)} for i, val in enumerate(port_equity)],
            'spy': [{'x': i, 'y': round(val, 2)} for i, val in enumerate(spy_equity)]
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

# --- ENDPOINT 3: TICKER LISTE ---

@app.get("/tickers")
def get_available_tickers():
    return {"tickers": TICKER_UNIVERSE}

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)