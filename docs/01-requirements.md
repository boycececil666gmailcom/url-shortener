# Requirements

## Functional Requirements
- Given a long URL, generate a short URL (typically 7-10 characters)
- When a user accesses a short URL, redirect to the original long URL (HTTP 301/302)
- Short URLs should be as short as possible
- Links should not expire (unless explicitly set)

## Non-Functional Requirements
- **Scale**: Billions of URLs, millions of redirects per second
- **Availability**: 99.99%+ uptime (highly available)
- **Latency**: Redirects should complete in < 100ms
- **Durability**: Data must not be lost
- **Consistency**: Eventual consistency is acceptable (short URL must resolve quickly after creation)

## Traffic Estimation
- Assume 100M new URLs/month (~40 new URLs/sec write)
- Assume 10:1 read:write ratio -> ~400M redirects/month (~400 reads/sec)
- With enterprise scale, plan for 10x-100x headroom: ~4000 reads/sec, ~400 writes/sec
