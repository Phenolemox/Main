from fastapi import FastAPI

app = FastAPI(title="PCF Fight Manager Engine")

@app.get("/health")
def health():
    return {"ok": True}
