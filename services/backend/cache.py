import json
import os

import redis.asyncio as aioredis

REDIS_URL = os.environ["REDIS_URL"]

# TTL for cached URL entries: 24 hours.
# After this, the entry is automatically evicted and the next request will
# fetch from Postgres and warm the cache again.
_CACHE_TTL_SECONDS = 60 * 60 * 24

# Module-level pool, created once at startup (mirrors the pattern in database.py).
redis_pool: aioredis.Redis | None = None


async def create_redis_pool() -> None:
    """Open the Redis connection pool. Call this once at app startup."""
    global redis_pool
    redis_pool = aioredis.from_url(REDIS_URL, decode_responses=True)


async def close_redis_pool() -> None:
    """Close the Redis connection pool. Call this at app shutdown."""
    if redis_pool:
        await redis_pool.aclose()


def _cache_key(short_url: int) -> str:
    """Canonical Redis key for a given short URL."""
    return f"url:{short_url}"


async def get_cached_url(short_url: int) -> dict | None:
    """Return the cached URL row for short_url, or None on a cache miss."""
    raw = await redis_pool.get(_cache_key(short_url))
    if raw is None:
        return None
    return json.loads(raw)


async def set_cached_url(row: dict) -> None:
    """Store a URL row in the cache.

    The row must contain at least 'id', 'long_url', and 'created_at'.
    'created_at' is serialised as an ISO-8601 string so JSON can handle it.
    """
    payload = {
        "short_url": row["short_url"],
        "long_url": row["long_url"],
        # created_at is a datetime object from asyncpg — convert to string
        "created_at": row["created_at"].isoformat(),
    }
    await redis_pool.set(
        _cache_key(row["short_url"]),
        json.dumps(payload),
        ex=_CACHE_TTL_SECONDS,
    )
