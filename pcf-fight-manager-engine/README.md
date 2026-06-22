# PCF Fight Manager Engine

MVP engine for PCF Fight Manager.

Folder created for this task: `pcf-fight-manager-engine`.

## Stack

- FastAPI
- SQLite
- HTML/CSS/JS
- Canvas UI

## Run locally

```bash
cd pcf-fight-manager-engine
python -m venv .venv
pip install -r requirements.txt
uvicorn app.main:app --reload
```

Open `http://127.0.0.1:8000`.

## MVP modules

- login
- state
- events
- event fights
- bets
- market
- first fighter claim
- training
- random fight calculation
- manual admin result
