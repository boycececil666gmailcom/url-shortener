"""
API Gateway — thin transparent proxy.

Responsibilities:
  - Receive HTTP requests from the end user
  - (Future) validate JWT, rate-limit, async kafka pipeline
  - Forward the request to the appropriate internal service via httpx
  - Return the response to the end user

No business logic lives here.
"""

from contextlib import asynccontextmanager

import httpx
from fastapi import FastAPI, HTTPException, Request, Response


# ── Internal service URLs ─────────────────────────────────────────────────────
# These are Docker internal hostnames — not exposed to the outside world.
SHORTENER_URL = "http://shortener:8001"


# ── Shared async httpx client ─────────────────────────────────────────────────
# A single client is reused across requests (connection pool).
_http_client: httpx.AsyncClient | None = None


@asynccontextmanager
async def lifespan(app: FastAPI):
    """Create the shared HTTP client on startup; close it on shutdown."""
    global _http_client
    _http_client = httpx.AsyncClient(timeout=10.0)
    yield
    await _http_client.aclose()


def get_client() -> httpx.AsyncClient:
    if _http_client is None:
        raise RuntimeError("HTTP client not initialised")
    return _http_client


# ── App ───────────────────────────────────────────────────────────────────────

app = FastAPI(title="API Gateway", version="0.1.0", lifespan=lifespan)


# ── Health ────────────────────────────────────────────────────────────────────

@app.get("/health")
async def health():
    return {"status": "ok"}


# ── Write Path ────────────────────────────────────────────────────────────────

@app.post("/api/v1/shorten", status_code=201)
async def shorten_url(request: Request):
    """Forward POST /api/v1/shorten to the Shortener service."""
    body = await request.body()
    headers = {"Content-Type": "application/json"}

    resp = await get_client().post(
        f"{SHORTENER_URL}/shorten",
        content=body,
        headers=headers,
    )

    _raise_for_upstream_error(resp)
    return Response(
        content=resp.content,
        status_code=resp.status_code,
        media_type="application/json",
    )


# ── Read Path ─────────────────────────────────────────────────────────────────

@app.get("/api/v1/urls/{short_url}")
async def get_url(short_url: int):
    """Forward GET /api/v1/urls/{short_url} to the Shortener service."""
    resp = await get_client().get(f"{SHORTENER_URL}/urls/{short_url}")
    _raise_for_upstream_error(resp)
    return Response(
        content=resp.content,
        status_code=resp.status_code,
        media_type="application/json",
    )


@app.get("/r/{short_url}")
async def redirect(short_url: int):
    """Forward redirect requests to the Shortener service."""
    resp = await get_client().get(
        f"{SHORTENER_URL}/r/{short_url}",
        follow_redirects=False,  # let the 302 pass back to the browser as-is
    )
    _raise_for_upstream_error(resp)
    return Response(
        content=resp.content,
        status_code=resp.status_code,
        headers=dict(resp.headers),
    )


# ── Helpers ───────────────────────────────────────────────────────────────────

def _raise_for_upstream_error(resp: httpx.Response) -> None:
    """Re-raise 4xx/5xx responses from upstream as FastAPI HTTPExceptions."""
    if resp.status_code >= 400:
        try:
            detail = resp.json().get("detail", resp.text)
        except Exception:
            detail = resp.text
        raise HTTPException(status_code=resp.status_code, detail=detail)
