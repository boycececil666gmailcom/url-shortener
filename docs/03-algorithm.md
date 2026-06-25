# URL Shortening Algorithm

## Base62 Encoding of Auto-Incremented ID
- Encode a sequential database ID (e.g., 12345) into Base62 (a-z, A-Z, 0-9)
- ID 12345 -> "c5" (very short)
- **Pros**: Simple, deterministic, short URLs, no collisions
- **Cons**: Sequential IDs are guessable/enumerable (security concern)