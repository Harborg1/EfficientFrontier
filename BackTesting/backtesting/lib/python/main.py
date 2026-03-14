from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
import yfinance as yf
import pandas as pd
import numpy as np
from typing import List, Dict, Optional

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
    returns_annual = returns_daily.mean() * 250
    cov_annual = returns_daily.cov() * 250

    port_returns = []
    port_volatility = []
    stock_weights = []

    # 1. Kør simuleringen (uden 'continue' check)
    for _ in range(num_portfolios):
        # 1. Generer vægte der altid summerer til 1.0 (Dirichlet er god til dette)
        weights = np.random.dirichlet(np.ones(num_assets), size=1)[0]

        # 2. "Rescale" logik: Hvis en vægt er over max_weight, 
        # så tvinger vi den ned og omfordeler resten proportionalt.
        # Vi kører det et par gange for at sikre, at alt overholdes.
        for _ in range(10): 
            if np.any(weights > max_weight):
                # Find dem der er for store
                too_high = weights > max_weight
                excess = weights[too_high] - max_weight
                weights[too_high] = max_weight
                
                # Find dem der er under grænsen og kan tage imod det overskydende
                too_low = weights < max_weight
                if total_excess := excess.sum():
                    # Omfordel proportionalt til dem, der har plads
                    weights[too_low] += (weights[too_low] / weights[too_low].sum()) * total_excess
            else:
                break

        
        # Nu er 'weights' 100% garanteret at overholde max_weight og summere til 1.0
        returns = np.dot(weights, returns_annual)
        volatility = np.sqrt(np.dot(weights.T, np.dot(cov_annual, weights)))
        
        port_returns.append(returns)
        port_volatility.append(volatility)
        stock_weights.append(weights)

    # 2. Opbyg portfolio dictionary (ligesom din klasse)
    portfolio = {'Returns': port_returns, 'Volatility': port_volatility}
    for counter, symbol in enumerate(selected):
        portfolio[symbol+' weight'] = [weight[counter] for weight in stock_weights]

    # 3. Omdan til DataFrame og beregn Sharpe
    df = pd.DataFrame(portfolio)
    df['Sharpe'] = df['Returns'] / df['Volatility']

    # 4. Filtrer baseret på max_weight efter simuleringen
    weight_cols = [s + ' weight' for s in selected]
    df = df[df[weight_cols].max(axis=1) <= max_weight]
    
    if df.empty:
        return {"error": f"None of the {num_portfolios} portfolios met the max_weight constraint of {max_weight}."}

    # 5. Find vinderne
    best_sharpe_idx = df['Sharpe'].idxmax()
    max_sharpe_port = df.loc[best_sharpe_idx]

    least_var_idx = df['Volatility'].idxmin()
    min_vol_port = df.loc[least_var_idx]

    def extract_weights(port_series):
        return {symbol: round(float(port_series[symbol+' weight']), 4) for symbol in selected}

    # 6. Returner data (scatter_points er nu hele listen uden [::10])
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
        # Hent data for porteføljen + SPY
        all_tickers = list(set(data.tickers + ['SPY'])) # set fjerner dubletter
        df = yf.download(all_tickers, period=data.timeframe, auto_adjust=False)
        
        if df.empty or 'Adj Close' not in df:
            raise HTTPException(status_code=400, detail="Could not fetch market data")

        # Vi isolerer Adj Close og fjerner NaN
        prices = df['Adj Close'].dropna()
        returns = prices.pct_change().dropna()
        
        # Vi sikrer os, at vi kun regner på de tickers, der rent faktisk er i dataen
        valid_tickers = [t for t in data.tickers if t in returns.columns]
        
        if not valid_tickers:
             raise HTTPException(status_code=400, detail="No valid tickers found in data")

        # Beregn vægtet afkast (vi reskalerer vægte hvis en ticker mangler)
        # Dette sikrer at summen af vægte stadig er 1.0 (100%)
        current_weights = np.array([data.weights[t] for t in valid_tickers])
        current_weights /= current_weights.sum() 
        
        # Matrix multiplikation er hurtigere end sum() loopet
        port_returns = returns[valid_tickers].dot(current_weights)
        
        # Equity Curve (Base 100)
        port_equity = ((1 + port_returns).cumprod() * 100).tolist()
        spy_equity = ((1 + returns['SPY']).cumprod() * 100).tolist()
        
        return {
            'portfolio': [{'x': i, 'y': round(val, 2)} for i, val in enumerate(port_equity)],
            'spy': [{'x': i, 'y': round(val, 2)} for i, val in enumerate(spy_equity)]
        }
    except Exception as e:
        print(f"Backtest Error: {e}") # Godt for debugging
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/tickers")
def get_available_tickers():
    return {"tickers": TICKER_UNIVERSE}

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)
    