### Flow

```mermaid
---
config:
  layout: elk
  theme: neutral
---
sequenceDiagram
    participant C as Client
    participant CDN as CDN / LB
    participant R as Redis
    participant DB as Read Replica
    participant Q as Queue
    participant A as Analytics

    C ->> CDN: GET /:short_code
    CDN ->> R: Lookup short_code
    alt Cache HIT
        R -->> CDN: long_url
        CDN -->> C: 302 Found (Location: long_url)
        CDN -) Q: Async log redirect event
        Q ->> A: Store analytics data
    else Cache MISS
        R -->> CDN: null
        CDN ->> DB: SELECT long_url WHERE short_code = ?
        alt Found
            DB -->> CDN: long_url
            CDN ->> R: SET short_code → long_url (TTL)
            CDN -->> C: 302 Found (Location: long_url)
            CDN -) Q: Async log redirect event
            Q ->> A: Store analytics data
        else Not Found
            DB -->> CDN: null
            CDN -->> C: 404 Not Found
        end
    end
```


### Redirect Strategy: 301 vs 302

- **302 (Temporary) Redirect** — Recommended default
  - Does not cache the redirect in browsers/CDNs.
  - Allows tracking/analytics on each visit.
  - More flexible if the target URL needs to change later.

- **301 (Permanent) Redirect** — Alternative
  - Browser caches the redirect permanently.
  - Reduces server load but loses analytics capability.
  - Better for pure performance if analytics are not needed.

**Recommendation**: Use **302** by default for flexibility; offer 301 as an option.

## Get URL Info

Retrieves metadata about a short URL without redirecting.

### Endpoint

```
GET /api/v1/urls/:short_code
```

### Response (200 OK)

```json
{
    "short_code": "a3fX9kZ",
    "long_url": "https://www.example.com/very/long/path?query=param",
    "created_at": "2026-06-24T12:00:00Z"
}
```

### Flow

```mermaid
---
config:
  layout: elk
  theme: neutral
---
sequenceDiagram
    participant C as Client
    participant A as API Gateway
    participant R as Redis
    participant DB as Read Replica

    C ->> A: GET /api/v1/urls/:short_code
    A ->> R: Lookup short_code
    alt Cache HIT
        R -->> A: {short_code, long_url, created_at}
    else Cache MISS
        R -->> A: null
        A ->> DB: SELECT * WHERE short_code = ?
        DB -->> A: {short_code, long_url, created_at}
    end
    A -->> C: 200 OK {short_code, long_url, created_at}
```

1. Receive request for `/api/v1/urls/:short_code`.
2. Check **Redis cache**.
   - **Cache HIT**: Return URL metadata.
   - **Cache MISS**: Query the **read replica database**.
3. If found, return metadata. If not found, return 404.

### Error Responses

```
404 Not Found - Short code does not exist
429 Too Many Requests - Rate limit exceeded
500 Internal Server Error
```
