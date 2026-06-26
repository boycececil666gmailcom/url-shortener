# Storage Design

## Database (PostgreSQL)

### Schema

The `short_code` serves as the primary key directly — no  auto-increment ID column is needed.

```sql
CREATE TABLE urls (
    short_code  VARCHAR(12) PRIMARY KEY,
    long_url    TEXT NOT NULL,
    created_at  TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at  TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);
```

### Read-Replica Setup

- A single **primary** database handles all writes.
- One or more **read replicas** serve read queries, keeping the primary under less load.
- Replication is asynchronous

## Caching (Redis)

### Purpose

Most redirect traffic hits a small set of popular URLs. A Redis cache sits in front of the database so that hot mappings are served without touching the DB at all.


### Key Design

| Key | Value | TTL |
|-----|-------|-----|
| `short_code` | `long_url` | No expiration for frequently accessed entries; 1-hour TTL for cold entries |

### Cache Flow

```
Redirect request → Check Redis
  → HIT:  Return 302 redirect immediately
  → MISS: Query DB → Store result in Redis → Return 302 redirect
```

### Cache Invalidation

- **URL update**: Delete the old `short_code` entry from cache.
- **URL deletion**: Delete the entry from cache.
- **TTL-based eviction**: Stale entries are removed automatically when their TTL expires.

### Redis Cluster Topology

- Multi-master setup across availability zones.
- Minimum 3 masters + 3 replicas for high availability.

