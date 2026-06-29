# Storage Design

## Database (PostgreSQL)

### Schema
```sql
CREATE TABLE urls (
    short_url  BIGSERIAL PRIMARY KEY,
    long_url   TEXT        NOT NULL UNIQUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
```

## Caching (Redis)

### Key Design

| Key pattern | Value (JSON) | TTL |
|---|---|---|
| `url:{short_url}` | `{"short_url": 1, "long_url": "https://...", "created_at": "..."}` | 24 hours |

### Cache-aside Pattern

On every read (`GET /api/v1/urls/:short_url` or `GET /r/:short_url`):

1. Look up `url:{short_url}` in Redis
2. **Hit** → return immediately (sub-millisecond)
3. **Miss** → query Postgres, write result to Redis, return

### Latency Advantage

Repeated reads of the same URL are dramatically faster once cached:

| | Redis (cache hit) | PostgreSQL (cache miss) |
|---|---|---|
| Typical latency | < 1 ms | 5 – 20 ms |
| Network hops | 1 (API → Redis) | 2 (API → Postgres → API) |
| Disk I/O | None (in-memory) | Yes (index scan + page read) |
| Connection overhead | Persistent pool | Persistent pool |
| Scales with DB size | No | Yes — larger tables = slower |

> At 100 RPS, shaving 15 ms per read path request = **1.5 seconds of latency
> saved per second of traffic**. The benefit compounds under load because fewer
> Postgres connections are needed, reducing connection pool contention.
