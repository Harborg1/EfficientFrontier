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
    num_portfolios: int = 20000  # <--- Nu er dette vores MÅL, ikke vores startskud        
):
   # 1. DEFINER SELECTED FØRSTE GANG (Baseret på brugerens input)
    if not tickers:
        selected = ['AAPL', 'MSFT', 'GOOGL','TSLA', 'XOM','V' , 'JNJ', 'AMZN', 'WMT','ADBE']
    else:
        # Rens input og fjern duplikater
        selected = list(set([t.strip().upper() for t in tickers.split(",") if t.strip()]))


    selected = selected[:15] 
    selected.sort()
    num_assets = len(selected)

    # Sikkerhedstjek: Kan det overhovedet lade sig gøre matematisk?
    if num_assets * max_weight < 1.0:
        return {"error": f"Kan ikke summere til 100% med {num_assets} aktier og et max på {max_weight*100}%."}
    
    data = yf.download(selected, start=start_date, end=end_date, auto_adjust=False)
    if data.empty or 'Adj Close' not in data:
        return {"error": "Could not retrieve data for the specified tickers."}
    
    table = data['Adj Close'].dropna(axis=1, how='all').dropna()
    
    selected = list(table.columns) 
    num_assets = len(selected)
    
    returns_daily = table.pct_change().dropna()
    
    # Vi bruger .values for at køre rene, lynhurtige NumPy beregninger
    returns_annual = (returns_daily.mean() * 250).values 
    cov_annual = (returns_daily.cov() * 250).values

    # --- 1. BATCHED REJECTION SAMPLING ---
    valid_weights_list = []
    batch_size = 50000  # Vi skyder med spredehagl (50k ad gangen)
    max_attempts = 100  # Sikkerhedsventil (så API'et ikke hænger i en uendelig løkke)
    attempts = 0
    total_valid = 0

    while total_valid < num_portfolios and attempts < max_attempts:
        attempts += 1
        
        # Dirichlet er den matematisk perfekte måde at generere vægte, der summerer til 1
        w_batch = np.random.dirichlet(np.ones(num_assets), size=batch_size)
        
        # Find dem, hvor ALLE aktier overholder max_weight
        mask = np.all(w_batch <= max_weight, axis=1)
        valid_ones = w_batch[mask]
        
        if len(valid_ones) > 0:
            valid_weights_list.append(valid_ones)
            total_valid += len(valid_ones)

    if not valid_weights_list:
        return {"error": "Kravene var så stramme, at vi ikke kunne finde nogen lovlige porteføljer. Prøv at hæve max_weight."}

    # Saml alle de godkendte fra vores batches i én stor matrix
    valid_weights = np.vstack(valid_weights_list)
    
    # Klip det overskydende af, så vi har PRÆCIS det antal, brugeren bad om (f.eks. 20.000)
    valid_weights = valid_weights[:num_portfolios]

    # --- 2. BEREGN PERFORMANCE FOR DE GODKENDTE ---
    # Matrix-multiplikation (Lynhurtigt for alle overlevende porteføljer på én gang)
    port_returns = np.dot(valid_weights, returns_annual)
    port_volatility = np.sqrt(np.sum(np.dot(valid_weights, cov_annual) * valid_weights, axis=1))

    # --- 3. OPBYG DATAFRAME ---
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


class SimulationRequest(BaseModel):
    tickers: List[str]
    weights: Dict[str, float]
    timeframe: str = "2y"  # Hvor meget historik skal vi lære fra?
    days_to_sim: int = 252 # Hvor mange handelsdage skal vi spå om?
    simulations: int = 1000

@app.post("/simulate")
async def simulate_portfolio(data: SimulationRequest):
    try:
        # 1. Hent historisk data for at få "opskriften" på de daglige afkast
        df = yf.download(data.tickers, period=data.timeframe, auto_adjust=False)['Adj Close']
        if df.empty:
            raise HTTPException(status_code=400, detail="Kunne ikke hente historik til simulation")

        # 2. Beregn porteføljens historiske dagsafkast
        returns = df.pct_change().dropna()
        valid_tickers = [t for t in data.tickers if t in returns.columns]
        
        w_array = np.array([data.weights[t] for t in valid_tickers])
        w_array /= w_array.sum()
        
        # Dette er vores "pulje" af historiske hændelser
        port_daily_history = returns[valid_tickers].dot(w_array).values

        # 3. Bootstrapping: Træk tilfældige dage fra historikken
        # Matrix: [antal dage frem] x [antal simulationer]
        sim_rets = np.random.choice(
            port_daily_history, 
            size=(data.days_to_sim, data.simulations), 
            replace=True
        )

        # 4. Beregn kumulativ vækst (vi starter ved kurs 100)
        # np.cumprod(1 + r) regner rentes rente effekten
        paths = np.cumprod(1 + sim_rets, axis=0) * 100
        
        # Tilføj startpunktet (dag 0 = 100) til alle percentiler
        def prepare_path(p_values):
            return [100.0] + [round(float(v), 2) for v in p_values]

        # 5. Udregn de statistiske bånd (viften)
        # Vi tager tværsnittet af alle 1000 simulationer for hver dag
        forecast = {
            "p95": prepare_path(np.percentile(paths, 95, axis=1)),
            "p75": prepare_path(np.percentile(paths, 75, axis=1)),
            "median": prepare_path(np.percentile(paths, 50, axis=1)),
            "p25": prepare_path(np.percentile(paths, 25, axis=1)),
            "p5": prepare_path(np.percentile(paths, 5, axis=1)),
        }

        # 6. Ekstra indsigt: Sandsynlighed for tab
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
    
@app.get("/tickers")
def get_available_tickers():
    return {"tickers": TICKER_UNIVERSE}

if __name__ == "__main__":

    port = int(os.environ.get("PORT", 8000))
    
    uvicorn.run(app, host="0.0.0.0", port=port)
