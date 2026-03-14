from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
import pandas as pd
import yfinance as yf
from typing import List, Dict

app = FastAPI()

# Tilføj CORS så din Flutter app kan få adgang
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"], 
    allow_methods=["*"],
    allow_headers=["*"],
)

class BacktestRequest(BaseModel):
    tickers: List[str]
    weights: Dict[str, float]
    timeframe: str = "1y"

@app.post("/backtest")
async def backtest(data: BacktestRequest):
    try:
        # Hent data for portefølje + benchmark
        all_tickers = data.tickers + ['SPY']
        df = yf.download(all_tickers, period=data.timeframe)['Adj Close']
        
        if df.empty:
            raise HTTPException(status_code=400, detail="Kunne ikke hente data")

        # Beregn daglige afkast og fjern manglende værdier
        returns = df.pct_change().dropna()
        
        # Beregn porteføljeafkast (vægtet sum)
        port_returns = sum(returns[t] * data.weights[t] for t in data.tickers)
        
        # Konverter til Equity Curve (startværdi 100)
        port_equity = ((1 + port_returns).cumprod() * 100).tolist()
        spy_equity = ((1 + returns['SPY']).cumprod() * 100).tolist()
        
        return {
            'portfolio': [{'x': i, 'y': round(val, 2)} for i, val in enumerate(port_equity)],
            'spy': [{'x': i, 'y': round(val, 2)} for i, val in enumerate(spy_equity)]
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)
