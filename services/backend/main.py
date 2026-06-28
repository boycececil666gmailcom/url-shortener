from contextlib import asynccontextmanager

import asyncpg
from fastapi import Depends, FastAPI, HTTPException
from fastapi.responses import RedirectResponse

from .crud import get_or_create_url, get_url_by_id
from .database import close_pool, create_pool, get_db
from .schemas import ShortenRequest, URLCreateResponse, URLLookupResponse


@asynccontextmanager
async def lifespan(app: FastAPI):
    """Open the DB pool and create the table on startup; close pool on shutdown."""
    await create_pool()

    # Create the urls table if it doesn't exist yet.
    from .database import pool
    async with pool.acquire() as conn:
        await conn.execute("""
            CREATE TABLE IF NOT EXISTS urls (
                id         BIGSERIAL PRIMARY KEY,
                long_url   TEXT        NOT NULL UNIQUE,
                created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
            )
        """)

    yield

    await close_pool()


app = FastAPI(title="URL Shortener", version="0.1.0", lifespan=lifespan)


# ── Health ────────────────────────────────────────────────────────────────────

@app.get("/health")
async def health():
    return {"status": "ok"}


# ── Write Path ────────────────────────────────────────────────────────────────

@app.post("/api/v1/shorten", response_model=URLCreateResponse, status_code=201)
async def shorten_url(
    body: ShortenRequest,
    conn: asyncpg.Connection = Depends(get_db),
):
    """Generate a short URL from a given long URL.

    Idempotent: submitting the same long_url twice returns the same short_code.
    """
    url_row = await get_or_create_url(conn, str(body.long_url))
    return URLCreateResponse(
        short_code=url_row["id"],
        long_url=url_row["long_url"],
        created_at=url_row["created_at"],
    )


# ── Read Path ─────────────────────────────────────────────────────────────────

@app.get("/api/v1/urls/{short_code}", response_model=URLLookupResponse)
async def get_url(
    short_code: int,
    conn: asyncpg.Connection = Depends(get_db),
):
    """Look up a short code and return the original long URL."""
    url_row = await get_url_by_id(conn, short_code)
    if url_row is None:
        raise HTTPException(status_code=404, detail="Short URL not found")
    return URLLookupResponse(
        short_code=url_row["id"],
        long_url=url_row["long_url"],
        created_at=url_row["created_at"],
    )


@app.get("/r/{short_code}")
async def redirect(
    short_code: int,
    conn: asyncpg.Connection = Depends(get_db),
):
    """Redirect to the original long URL (HTTP 302)."""
    url_row = await get_url_by_id(conn, short_code)
    if url_row is None:
        raise HTTPException(status_code=404, detail="Short URL not found")
    return RedirectResponse(url=url_row["long_url"], status_code=302)
