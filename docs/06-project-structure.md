# Project Structure

```
url-shortener/
  cmd/
    server/
      main.go              # Application entry point
  internal/
    config/
      config.go            # Configuration management
    handler/
      url_handler.go       # HTTP request handlers
    middleware/
      logging.go           # Request logging middleware
      ratelimit.go         # Rate limiting middleware
    model/
      url.go               # Data models
    repository/
      url_repository.go    # Database access layer
    service/
      url_service.go       # Business logic (shortening, validation)
    cache/
      redis_cache.go       # Redis cache operations
    encoder/
      base62.go            # Random Base62 short code generation
  migrations/
    001_create_urls.sql    # Database migration
  configs/
    config.yaml            # Configuration file
  go.mod
  go.sum
  Dockerfile
  docker-compose.yaml      # Local dev environment (PostgreSQL + Redis)
```

## Directory Responsibilities

| Directory | Purpose |
|-----------|---------|
| `cmd/server/` | Application entry point, wires dependencies, starts HTTP server |
| `internal/config/` | Loads and validates configuration from YAML/env vars |
| `internal/handler/` | HTTP handlers for API endpoints |
| `internal/middleware/` | Cross-cutting concerns (logging, rate limiting, auth) |
| `internal/model/` | Data structures and domain types |
| `internal/repository/` | Database access layer (CRUD operations) |
| `internal/service/` | Business logic (URL shortening, validation) |
| `internal/cache/` | Redis cache operations |
| `internal/encoder/` | Random Base62 short code generation |
| `migrations/` | SQL migration files for database schema |
| `configs/` | Configuration files (YAML) |
