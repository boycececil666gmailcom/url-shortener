"""
Integration tests for the URL Shortener API.

Requires the Docker Compose stack to be running:
    docker compose up -d

Run with:
    pytest test/ -v
"""

import time
import uuid

import pytest
import httpx

BASE_URL = "http://localhost:8000"

# ── Fixtures ──────────────────────────────────────────────────────────────────

@pytest.fixture(scope="session")
def client():
    """Shared HTTP client for the whole test session."""
    with httpx.Client(base_url=BASE_URL, timeout=10.0) as c:
        yield c


# ── Health ────────────────────────────────────────────────────────────────────

class TestHealth:
    def test_health_returns_200(self, client):
        """GET /health should return HTTP 200."""
        response = client.get("/health")
        assert response.status_code == 200

    def test_health_body(self, client):
        """GET /health should return {status: ok}."""
        response = client.get("/health")
        assert response.json() == {"status": "ok"}


# ── Shorten (POST /api/v1/shorten) ────────────────────────────────────────────

class TestShorten:
    SAMPLE_URL = "https://www.example.com/some/very/long/path"

    def test_shorten_returns_201(self, client):
        """POST /api/v1/shorten should return HTTP 201 Created."""
        response = client.post("/api/v1/shorten", json={"long_url": self.SAMPLE_URL})
        assert response.status_code == 201

    def test_shorten_response_shape(self, client):
        """Response body should contain short_code, long_url, and created_at."""
        response = client.post("/api/v1/shorten", json={"long_url": self.SAMPLE_URL})
        body = response.json()
        assert "short_url" in body
        assert "long_url" in body
        assert "created_at" in body

    def test_shorten_short_code_is_integer(self, client):
        """short_code should be a positive integer."""
        response = client.post("/api/v1/shorten", json={"long_url": self.SAMPLE_URL})
        short_url = response.json()["short_url"]
        assert isinstance(short_url, int)
        assert short_url > 0

    def test_shorten_idempotent(self, client):
        """Submitting the same URL twice should return the same short_code."""
        r1 = client.post("/api/v1/shorten", json={"long_url": self.SAMPLE_URL})
        r2 = client.post("/api/v1/shorten", json={"long_url": self.SAMPLE_URL})
        assert r1.json()["short_url"] == r2.json()["short_url"]

    def test_shorten_invalid_url_returns_422(self, client):
        """POST with a non-URL string should return HTTP 422 Unprocessable Entity."""
        response = client.post("/api/v1/shorten", json={"long_url": "not-a-valid-url"})
        assert response.status_code == 422

    def test_shorten_missing_body_returns_422(self, client):
        """POST with an empty body should return HTTP 422."""
        response = client.post("/api/v1/shorten", json={})
        assert response.status_code == 422


# ── Lookup (GET /api/v1/urls/{short_code}) ────────────────────────────────────

class TestLookup:
    LOOKUP_URL = "https://www.lookup-test.com/page"

    @pytest.fixture(scope="class")
    def short_url(self, client):
        """Create a short URL once and reuse its code across lookup tests."""
        response = client.post("/api/v1/shorten", json={"long_url": self.LOOKUP_URL})
        assert response.status_code == 201
        return response.json()["short_url"]

    def test_lookup_returns_200(self, client, short_url):
        """GET /api/v1/urls/{short_url} should return HTTP 200."""
        response = client.get(f"/api/v1/urls/{short_url}")
        assert response.status_code == 200

    def test_lookup_response_shape(self, client, short_url):
        """Lookup response should contain short_url, long_url, and created_at."""
        body = client.get(f"/api/v1/urls/{short_url}").json()
        assert "short_url" in body
        assert "long_url" in body
        assert "created_at" in body

    def test_lookup_long_url_matches(self, client, short_url):
        """Returned long_url should match the originally submitted URL."""
        body = client.get(f"/api/v1/urls/{short_url}").json()
        assert body["long_url"] == self.LOOKUP_URL

    def test_lookup_nonexistent_code_returns_404(self, client):
        """GET with a short_url that doesn't exist should return HTTP 404."""
        response = client.get("/api/v1/urls/999999")
        assert response.status_code == 404


# ── Redirect (GET /r/{short_code}) ───────────────────────────────────────────

class TestRedirect:
    REDIRECT_URL = "https://www.redirect-test.com/destination"

    @pytest.fixture(scope="class")
    def short_url(self, client):
        """Create a short URL once and reuse its code across redirect tests."""
        response = client.post("/api/v1/shorten", json={"long_url": self.REDIRECT_URL})
        assert response.status_code == 201
        return response.json()["short_url"]

    def test_redirect_points_to_correct_destination(self, client, short_url):
        """GET /r/{short_url} should issue a 302 pointing to the original URL.

        We stop at the 302 instead of following it — testing that the server
        issues the correct Location header is sufficient. Actually connecting
        to the destination URL is outside the server's responsibility and would
        require the destination to be reachable from this machine.
        """
        response = client.get(f"/r/{short_url}", follow_redirects=False)
        assert response.status_code == 302
        assert response.headers["location"] == self.REDIRECT_URL

    def test_redirect_status_is_302(self, client, short_url):
        """The initial response before following should be an HTTP 302."""
        response = client.get(f"/r/{short_url}", follow_redirects=False)
        assert response.status_code == 302

    def test_redirect_location_header(self, client, short_url):
        """Location header should point to the original long URL."""
        response = client.get(f"/r/{short_url}", follow_redirects=False)
        assert response.headers["location"] == self.REDIRECT_URL

    def test_redirect_nonexistent_code_returns_404(self, client):
        """GET /r/{short_url} with an unknown code should return HTTP 404."""
        response = client.get("/r/999999", follow_redirects=False)
        assert response.status_code == 404


# ── Redis Latency Benchmark ────────────────────────────────────────────────────────────

class TestCacheLatency:
    """Demonstrate the latency advantage of Redis cache-aside.

    The first request is a cache MISS — FastAPI must query Postgres.
    Subsequent requests are cache HITs — FastAPI returns directly from Redis.
    We assert that the average cache-hit time is at least 2× faster than
    the cold miss, proving Redis is providing a real speedup.
    """

    REPEAT = 10  # number of warm requests to average

    def test_cache_hit_is_faster_than_miss(self, client):
        # ── Unique URL per run: guarantees a cold miss every time ────────────────
        # A fixed URL would be cached after the first run (TTL = 24 h),
        # turning subsequent "cold" requests into warm Redis hits and making
        # the benchmark invalid. uuid4 ensures the URL is always brand-new.
        unique_url = f"https://www.latency-benchmark.com/{uuid.uuid4()}"

        # ── Setup: create the URL so it exists in Postgres ──────────────────────
        resp = client.post("/api/v1/shorten", json={"long_url": unique_url})
        assert resp.status_code == 201
        short_url = resp.json()["short_url"]

        # ── Cold request: first fetch warms the Redis cache ──────────────────────
        t0 = time.perf_counter()
        r = client.get(f"/api/v1/urls/{short_url}")
        cold_ms = (time.perf_counter() - t0) * 1000
        assert r.status_code == 200, "Cold request failed"

        # ── Warm requests: subsequent fetches are served from Redis ────────────
        warm_times = []
        for _ in range(self.REPEAT):
            t0 = time.perf_counter()
            r = client.get(f"/api/v1/urls/{short_url}")
            warm_times.append((time.perf_counter() - t0) * 1000)
            assert r.status_code == 200, "Warm request failed"

        avg_warm_ms = sum(warm_times) / len(warm_times)

        print(f"\n  Cold (Postgres): {cold_ms:.2f} ms")
        print(f"  Warm  (Redis):   {avg_warm_ms:.2f} ms  "
              f"(avg of {self.REPEAT} requests)")
        print(f"  Speedup:         {cold_ms / avg_warm_ms:.1f}×")

        # Redis should be at least 2× faster than a cold Postgres hit.
        # On localhost the gap is usually 5–20× — 2× is a conservative floor.
        assert avg_warm_ms < cold_ms / 2, (
            f"Expected cache hits ({avg_warm_ms:.2f} ms) to be at least 2× "
            f"faster than the cold miss ({cold_ms:.2f} ms)"
        )
