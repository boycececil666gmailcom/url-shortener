from fastapi import FastAPI

app = FastAPI(title="URL Shortener", version="0.1.0")


@app.get("/health")
async def health():
    return {"status": "ok"}


# --- Write Path ---

@app.post("/api/v1/shorten", status_code=201)
async def shorten_url():
    """Generate a short URL from a given long URL."""
    # TODO: implement with database layer
    return {"detail": "Not implemented yet"}


# --- Read Path ---

@app.get("/api/v1/urls/{short_code}")
async def get_url(short_code: str):
    """Look up a short URL and return the original long URL."""
    # TODO: implement with database + cache layer
    return {"detail": "Not implemented yet"}


@app.get("/r/{short_code}")
async def redirect(short_code: str):
    """Redirect to the original long URL (HTTP 301/302)."""
    # TODO: implement with cache + database lookup
    return {"detail": "Not implemented yet"}
