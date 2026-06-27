import asyncpg


async def get_or_create_url(conn: asyncpg.Connection, long_url: str) -> dict:
    """Insert long_url if it doesn't exist, then return the row.

    Uses INSERT ... ON CONFLICT DO NOTHING so concurrent requests for the
    same URL are safe — only one row is ever created.
    """
    # Try to insert; if the URL already exists the statement does nothing.
    await conn.execute(
        """
        INSERT INTO urls (long_url)
        VALUES ($1)
        ON CONFLICT (long_url) DO NOTHING
        """,
        long_url,
    )

    # Fetch the row (whether we just inserted it or it already existed).
    row = await conn.fetchrow(
        "SELECT id, long_url, created_at FROM urls WHERE long_url = $1",
        long_url,
    )
    return dict(row)


async def get_url_by_id(conn: asyncpg.Connection, url_id: int) -> dict | None:
    """Return the URL row for a given integer short code, or None."""
    row = await conn.fetchrow(
        "SELECT id, long_url, created_at FROM urls WHERE id = $1",
        url_id,
    )
    return dict(row) if row is not None else None
