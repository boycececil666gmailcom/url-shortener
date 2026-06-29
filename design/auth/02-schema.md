# Auth Service Databases

This document defines the data storage for the Authentication Service, which uses **PostgreSQL** for persistent user data and **Redis** for fast, expiring refresh tokens.

## 1. User Database (PostgreSQL)

Stores the user identities and their hashed passwords.

```sql
CREATE TABLE users (
    id SERIAL PRIMARY KEY,
    username VARCHAR(50) UNIQUE NOT NULL,
    password_hash VARCHAR(255) NOT NULL, -- The bcrypt hash (includes salt)
    created_at TIMESTAMPTZ DEFAULT NOW()
);
```

### Columns
- `id`: Unique identifier for the user. Embedded in the JWT as the `sub` (subject) claim.
- `username`: The login name. Must be unique.
- `password_hash`: The output of the `bcrypt` algorithm. We **never** store plain text here.

---

## 2. Token Database (Redis)

Stores the opaque refresh tokens used to obtain new access tokens. Because tokens naturally expire and need fast lookups, Redis is the ideal storage.

**Key Pattern:**
`refresh_token:{token_string}`

**Value:**
The `user_id` associated with the token.

**TTL (Time To Live):**
Set to the expiration time of the refresh token (e.g., 30 days). Redis will automatically delete the token when it expires.

### Example Redis Commands
```redis
# When logging in (saving a new refresh token for user 123, expires in 30 days):
SET refresh_token:a3f9b2c1d4e5f6a7 123 EX 2592000

# When verifying a refresh token:
GET refresh_token:a3f9b2c1d4e5f6a7
> "123"

# When logging out (revoking the token):
DEL refresh_token:a3f9b2c1d4e5f6a7
```


