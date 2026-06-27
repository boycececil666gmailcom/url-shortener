# Storage Design

## Database (PostgreSQL)

### Schema
```sql
CREATE TABLE urls (
    id         BIGSERIAL PRIMARY KEY,
    long_url   TEXT      NOT NULL UNIQUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
```

## Caching (Redis)


### Key Design

| Key | Value | TTL |
|-----|-------|-----|
| `short_url` | `long_url` | No expiration for frequently accessed entries; 1-hour TTL for cold entries |

