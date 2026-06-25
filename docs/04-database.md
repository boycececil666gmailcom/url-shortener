# Database Design

## Primary Table: `urls`

```sql
CREATE TABLE urls (
    id          BIGSERIAL PRIMARY KEY,
    short_code  VARCHAR(12) NOT NULL UNIQUE,
    long_url    TEXT NOT NULL,
    created_at  TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at  TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX idx_short_code ON urls(short_code);
```

## Database Choice: PostgreSQL

- ACID compliance ensures data integrity
- Excellent performance for read-heavy workloads with proper indexing
- Mature partitioning support for scaling to billions of rows
- Strong replication ecosystem (streaming, logical)

## Scaling the Database

- **Read Replicas**: Multiple read replicas behind a load balancer for read-heavy traffic
- **Partitioning**: Range-partition `urls` table by `id` or hash-partition by `short_code`
- **Sharding** (future): Shard by `short_code` hash if single cluster becomes insufficient
- **Connection Pooling**: PgBouncer between API servers and PostgreSQL
