# Caching Strategy

## Redis Cluster

- Cache hot short_code -> long_url mappings
- TTL: No expiration for frequently accessed URLs, 1-hour TTL for cold entries
- Expected cache hit rate: 80-90% for typical traffic patterns

## Cache Flow

```
Redirect Request -> Check Redis
  -> Cache HIT: Return 302 redirect immediately
  -> Cache MISS: Query DB -> Store in Redis -> Return 302 redirect
```

## Cache Invalidation

- On URL update: Delete the old short_code entry from cache
- On URL deletion: Delete from cache
- TTL-based natural eviction for stale entries

## Redis Cluster Topology

- Multi-master setup across availability zones
- Minimum 3 masters + 3 replicas for high availability
