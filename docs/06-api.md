# API Design

## Endpoints

### 1. Shorten URL

```
POST /api/v1/shorten
Content-Type: application/json

Request:
{
    "long_url": "https://www.example.com/very/long/path?query=param"
}

Response (201 Created):
{
    "short_url": "https://short.ly/a3fX9kZ",
    "short_code": "a3fX9kZ",
    "long_url": "https://www.example.com/very/long/path?query=param",
    "created_at": "2026-06-24T12:00:00Z"
}
```

### 2. Redirect (handled at route level)

```
GET /:short_code

Response: 302 Found
Location: https://www.example.com/very/long/path?query=param
```

### 3. Get URL Info

```
GET /api/v1/urls/:short_code

Response (200 OK):
{
    "short_code": "a3fX9kZ",
    "long_url": "https://www.example.com/very/long/path?query=param",
    "created_at": "2026-06-24T12:00:00Z"
}
```

## Error Responses

```
400 Bad Request - Invalid or missing long_url
404 Not Found - Short code does not exist
429 Too Many Requests - Rate limit exceeded
500 Internal Server Error
```

## Redirect Strategy: 301 vs 302

- **302 (Temporary) Redirect**: Recommended default
  - Does not cache the redirect in browsers/CDNs
  - Allows tracking/analytics on each visit
  - More flexible if you need to change the target later

- **301 (Permanent) Redirect**: Alternative
  - Browser caches the redirect permanently
  - Reduces server load but loses analytics capability
  - Better for pure performance if analytics not needed

**Recommendation**: Use **302** by default for flexibility, offer 301 as an option.
