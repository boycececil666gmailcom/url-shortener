# ── Base image ────────────────────────────────────────────────────────────────
FROM python:3.11-slim

# Keeps Python from buffering stdout/stderr (important for container logs)
ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1

# ── Install uv ────────────────────────────────────────────────────────────────
RUN pip install --no-cache-dir uv

# ── Working directory ─────────────────────────────────────────────────────────
WORKDIR /app

# ── Install dependencies (layer-cache friendly) ───────────────────────────────
# Copy only the dependency manifests first so Docker can cache this layer
# and skip re-installing when only application code changes.
COPY pyproject.toml uv.lock ./
RUN uv sync --frozen --no-dev

# ── Copy application source ───────────────────────────────────────────────────
COPY services/shortener/ ./shortener/

# ── Expose port ───────────────────────────────────────────────────────────────
EXPOSE 8001

# ── Run the server ────────────────────────────────────────────────────────────
# Internal service — not exposed to the host, only reachable inside Docker network.
CMD ["uv", "run", "uvicorn", "shortener.main:app", \
     "--host", "0.0.0.0", "--port", "8001", "--reload"]
