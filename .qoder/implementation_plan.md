# Containerize the Backend Service

Wrap the FastAPI backend in a Docker image so it can run in any environment reliably, and pair it with a `docker-compose.yml` that also spins up the PostgreSQL database (already called out in the existing DB integration plan). The result is a fully self-contained local dev environment where a single `docker compose up` starts everything.

---

## User Review Required

> [!IMPORTANT]
> The project currently uses **`uv`** as the package manager (via `uv.lock`). The Dockerfile will use `uv` to install dependencies inside the container for speed and lock-file fidelity. Let me know if you'd prefer plain `pip` instead.

> [!IMPORTANT]
> The existing `.qoder` DB integration plan expects a `docker-compose.yml` to already exist for PostgreSQL. This plan creates that file as part of the containerization work, so **both goals are satisfied together**.

---

## Open Questions

> [!NOTE]
> **Hot-reload in dev vs. production image?** The plan below creates a single `Dockerfile` that runs `uvicorn` with `--reload` for dev convenience. If you also want a lean production image (no reload, multi-stage build), just say the word and I'll add a second stage.

> [!NOTE]
> **Port mapping**: The plan exposes the FastAPI service on **host port 8000**. Fine to change if something else is already occupying that port.

---

## Proposed Changes

### Docker — new files at project root

#### [NEW] `Dockerfile`

- Base image: `python:3.11-slim` (matches `requires-python = ">=3.11"` in `pyproject.toml`)
- Install **`uv`** via pip in the image
- Copy `pyproject.toml` + `uv.lock` first (layer-cache friendly), run `uv sync --frozen --no-dev`
- Copy the rest of the source
- Expose port **8000**
- Default `CMD`: `uvicorn backend.main:app --host 0.0.0.0 --port 8000 --reload`

#### [NEW] `.dockerignore`

Exclude from the build context to keep the image lean:
- `.venv/` (dependencies are installed fresh inside the container)
- `.git/`, `.qoder/`, `design/`
- `__pycache__/`, `*.pyc`
- `.env`, `*.log`

#### [NEW] `docker-compose.yml`

Two services:

| Service | Image | Purpose |
|---|---|---|
| `api` | built from local `Dockerfile` | FastAPI backend |
| `db` | `postgres:16-alpine` | PostgreSQL database |

- `api` depends on `db` (with a health-check wait so Postgres is ready before the app starts)
- Environment variables passed to `api`:
  - `DATABASE_URL=postgresql://postgres:postgres@db:5432/urlshortener`
- Postgres credentials / database name match the existing DB plan (`urlshortener`, user `postgres`, password `postgres`)
- Named volume `postgres_data` for DB persistence
- Port mappings: `8000:8000` for the API, `5432:5432` for Postgres (useful for local tools like DBeaver)

---

### `.gitignore` — update

#### [MODIFY] [.gitignore](file:///c:/Users/boyce/OneDrive/Desktop/url-shortener/.gitignore)

Add Python/Docker entries that are currently missing:
- `__pycache__/`
- `*.pyc`
- `.venv/`
- `*.env` (already has `.env` but not the wildcard variant)

---

## Verification Plan

### Automated
- `docker compose build` — image builds without errors
- `docker compose up -d` — both containers start healthy
- `curl http://localhost:8000/health` — returns `{"status": "ok"}`

### Manual
- Confirm `docker ps` shows both `api` and `db` containers running
- Confirm the FastAPI interactive docs are accessible at `http://localhost:8000/docs`
