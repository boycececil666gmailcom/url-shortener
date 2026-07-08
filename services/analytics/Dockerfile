FROM python:3.12-slim

# Install uv
COPY --from=ghcr.io/astral-sh/uv:latest /uv /uvx /bin/

ENV UV_SYSTEM_PYTHON=1 \
    PYTHONUNBUFFERED=1

WORKDIR /app

# Install dependencies
COPY services/analytics/pyproject.toml services/analytics/uv.lock ./
RUN uv sync --frozen

# Copy application source code
COPY services/analytics/ ./analytics/


# Start the application
CMD ["uv", "run", "uvicorn", "analytics.main:app", "--host", "0.0.0.0", "--port", "8003", "--reload"]
