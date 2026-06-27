# PostgreSQL Database Integration

## Task 1: Set up Docker Compose for PostgreSQL
- Create `docker-compose.yml` at project root
- Configure PostgreSQL 16 with:
  - Port: 5432
  - Database: `urlshortener`
  - User/password: `postgres`/`postgres`
  - Volume for data persistence

## Task 2: Add asyncpg dependency
- Update `pyproject.toml` to add `asyncpg`
- Run `uv sync` to install

## Task 3: Create database module
- Create `backend/database.py` with:
  - Connection pool setup using `asyncpg.create_pool()`
  - `init_db()` — create connection pool on app startup
  - `close_db()` — close pool on app shutdown
  - `create_tables()` — execute the schema from design doc:
    ```sql
    CREATE TABLE urls (
        short_url   BIGSERIAL PRIMARY KEY,
        long_url    TEXT NOT NULL UNIQUE,
        created_at  TIMESTAMP WITH TIME ZONE DEFAULT NOW()
    );
    ```

## Task 4: Create database operations
- Add functions to `backend/database.py`:
  - `insert_url(long_url)` — INSERT with ON CONFLICT DO NOTHING, return short_url
  - `get_long_url(short_url)` — SELECT long_url by short_url
  - `get_short_url(long_url)` — SELECT short_url by long_url (for dedup)

## Task 5: Wire up FastAPI endpoints
- Update `backend/main.py`:
  - Register startup/shutdown events for DB pool
  - `POST /api/v1/shorten` — accept `{long_url}`, call `insert_url()`, return `{short_url, long_url, created_at}`
  - `GET /api/v1/urls/{short_code}` — call `get_long_url()`, return URL info or 404
  - `GET /r/{short_code}` — call `get_long_url()`, return HTTP 302 redirect or 404

## Task 6: Test the integration
- Start Docker container: `docker compose up -d`
- Start FastAPI server: `uv run uvicorn backend.main:app --reload`
- Test endpoints with curl:
  - POST to create short URL
  - GET to retrieve URL info
  - GET redirect endpoint
