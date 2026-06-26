# Write Path API
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
    participant S as Shortener Service
    participant R as Redis
    participant DB as Primary DB

    C ->> A: POST /api/v1/shorten {long_url}
    alt Invalid or missing long_url
        A -->> C: 400 Bad Request
    else Rate limit exceeded
        A -->> C: 429 Too Many Requests
    else Valid request
        A ->> S: Validate & shorten
        S ->> S: Generate random<br/>Base62 short_code
        S ->> DB: INSERT (short_code, long_url)
        alt Collision
            DB -->> S: Conflict
            S ->> S: Retry with new random code
            S ->> DB: INSERT (new short_code, long_url)
        end
        alt DB failure
            DB -->> S: Error
            S -->> A: Error
            A -->> C: 500 Internal Server Error
        else Success
            DB -->> S: OK (stored)
            S ->> R: SET short_code → long_url (pre-warm)
            S -->> A: {short_url, short_code, long_url, created_at}
            A -->> C: 201 Created
        end
    end
```





## Short Code Generation

### Approach: Random Base62 String

Each new URL gets a unique short code by picking 7 random characters from the Base62 alphabet (`a–z`, `A–Z`, `0–9`).

- 7 characters give roughly 3.5 trillion possible codes (62⁷), plenty of room before collisions become likely.
- The system checks for collisions and retries with a new random code if one occurs.

### Why Base62?

The short code is used as the primary key for all database lookups and index scans. The Base62 alphabet (`a–z`, `A–Z`, `0–9`) keeps the character set small and uniform, which means:

- **Fast index lookups** — simple byte-level comparison with no multi-byte or special-character edge cases.
- **Compact index size** — smaller B-tree nodes, better cache utilization.
- **URL-safe by default** — The Base62 alphabet consists solely of alphanumeric characters, avoiding reserved URL characters (such as `+`, `/`, `=`, or `-`). This ensures the short code can be embedded directly in URLs without requiring percent-encoding, keeping links clean and readable.

