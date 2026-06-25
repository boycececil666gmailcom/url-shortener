# URL Shortening Algorithm

## Option A: Base62 Encoding of Auto-Incremented ID
- Encode a sequential database ID (e.g., 12345) into Base62 (a-z, A-Z, 0-9)
- ID 12345 -> "c5" (very short)
- **Pros**: Simple, deterministic, short URLs, no collisions
- **Cons**: Sequential IDs are guessable/enumerable (security concern)

## Option B: Base62 Encoding of Hash (MD5/SHA256)
- Hash the long URL, take first N bytes, encode in Base62
- **Pros**: Non-sequential, harder to guess
- **Cons**: Collisions possible, need retry logic, longer codes needed

## Option C: Pre-generated Key Range (Key Generator Service)
- Dedicated key generator service hands out ranges of IDs to each API server
- Each server encodes its allocated range in Base62
- **Pros**: No single point of contention, works across distributed servers, non-sequential with randomization
- **Cons**: Additional service to manage

## Recommendation: Base62 Encoding with Hash + Collision Handling

- SHA256 hash the long URL + a salt, take first 7 bytes
- Encode in Base62 to get a ~9 character short code
- Check for collision in DB; if collision, append a counter and re-hash
- This gives non-guessable, reasonably short URLs with minimal collision rate

With 62^9 = ~13 trillion possible codes, collision probability is extremely low even at billions of URLs.
