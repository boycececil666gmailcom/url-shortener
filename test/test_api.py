"""
Integration tests for the URL Shortener — two-service architecture.

Stack under test:
    gateway   (FastAPI, port 8000) — the only public entry point
        └── shortener (FastAPI, port 8001) — internal, not tested directly
                └── PostgreSQL + Redis

All requests go through the gateway at localhost:8000, exactly as a real
client would. The shortener is an implementation detail; we never call it
directly here.

Requires the Docker Compose stack to be running:
    docker compose up -d

Run with:
    pytest test/ -v
"""

import time
import uuid

import httpx
import pytest

BASE_URL = "http://localhost:8000"


# ── Fixtures ──────────────────────────────────────────────────────────────────

@pytest.fixture(scope="session")
def client():
    """Shared HTTP client for the whole test session.

    scope="session" means one client (and one connection pool) is created
    for all tests — mirrors how a real caller behaves.
    """
    with httpx.Client(base_url=BASE_URL, timeout=10.0, follow_redirects=False) as c:
        yield c


# ── Health ────────────────────────────────────────────────────────────────────

class TestHealth:
    """The gateway exposes its own /health endpoint."""

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
        """Response body should contain short_url, long_url, and created_at."""
        response = client.post("/api/v1/shorten", json={"long_url": self.SAMPLE_URL})
        body = response.json()
        assert "short_url" in body
        assert "long_url" in body
        assert "created_at" in body

    def test_shorten_short_url_is_positive_integer(self, client):
        """short_url should be a positive integer."""
        response = client.post("/api/v1/shorten", json={"long_url": self.SAMPLE_URL})
        short_url = response.json()["short_url"]
        assert isinstance(short_url, int)
        assert short_url > 0

    def test_shorten_idempotent(self, client):
        """Submitting the same long URL twice must return the same short_url."""
        r1 = client.post("/api/v1/shorten", json={"long_url": self.SAMPLE_URL})
        r2 = client.post("/api/v1/shorten", json={"long_url": self.SAMPLE_URL})
        assert r1.json()["short_url"] == r2.json()["short_url"]

    def test_shorten_invalid_url_returns_422(self, client):
        """POST with a non-URL string should return HTTP 422 Unprocessable Entity.

        The gateway forwards the body to the shortener, which validates it with
        Pydantic. A 422 from the shortener is proxied back as-is.
        """
        response = client.post("/api/v1/shorten", json={"long_url": "not-a-valid-url"})
        assert response.status_code == 422

    def test_shorten_missing_body_returns_422(self, client):
        """POST with an empty JSON body should return HTTP 422."""
        response = client.post("/api/v1/shorten", json={})
        assert response.status_code == 422


# ── Lookup (GET /api/v1/urls/{short_url}) ────────────────────────────────────

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

    def test_lookup_nonexistent_returns_404(self, client):
        """GET with a short_url that does not exist should return HTTP 404.

        Verifies the gateway correctly proxies 404 errors from the shortener.
        """
        response = client.get("/api/v1/urls/999999999")
        assert response.status_code == 404


# ── Redirect (GET /r/{short_url}) ────────────────────────────────────────────

class TestRedirect:
    REDIRECT_URL = "https://www.redirect-test.com/destination"

    @pytest.fixture(scope="class")
    def short_url(self, client):
        """Create a short URL once and reuse its code across redirect tests."""
        response = client.post("/api/v1/shorten", json={"long_url": self.REDIRECT_URL})
        assert response.status_code == 201
        return response.json()["short_url"]

    def test_redirect_status_is_302(self, client, short_url):
        """GET /r/{short_url} should respond with HTTP 302."""
        response = client.get(f"/r/{short_url}")
        assert response.status_code == 302

    def test_redirect_location_header(self, client, short_url):
        """Location header should point to the original long URL.

        We stop at the 302 and inspect the Location header — we don't follow
        the redirect because the destination URL is outside our system.
        """
        response = client.get(f"/r/{short_url}")
        assert response.headers["location"] == self.REDIRECT_URL

    def test_redirect_nonexistent_returns_404(self, client):
        """GET /r/{short_url} with an unknown code should return HTTP 404."""
        response = client.get("/r/999999999")
        assert response.status_code == 404


# ── Cache Latency Benchmark ───────────────────────────────────────────────────

class TestCacheLatency:
    """Prove that Redis cache-aside provides a real latency advantage.

    First request = cache MISS (Postgres query + cache warm).
    Subsequent requests = cache HITs (Redis only).
    We assert the average warm time is at least 2× faster than the cold miss.
    """

    REPEAT = 10

    def test_cache_hit_is_faster_than_miss(self, client):
        # Unique URL guarantees a genuine cold miss every test run.
        # A fixed URL would be cached after the first run (TTL = 24 h).
        unique_url = f"https://www.latency-benchmark.com/{uuid.uuid4()}"

        # Create the URL so it exists in Postgres
        resp = client.post("/api/v1/shorten", json={"long_url": unique_url})
        assert resp.status_code == 201
        short_url = resp.json()["short_url"]

        # Cold request — warms the Redis cache
        t0 = time.perf_counter()
        r = client.get(f"/api/v1/urls/{short_url}")
        cold_ms = (time.perf_counter() - t0) * 1000
        assert r.status_code == 200, "Cold request failed"

        # Warm requests — served from Redis
        warm_times = []
        for _ in range(self.REPEAT):
            t0 = time.perf_counter()
            r = client.get(f"/api/v1/urls/{short_url}")
            warm_times.append((time.perf_counter() - t0) * 1000)
            assert r.status_code == 200, "Warm request failed"

        avg_warm_ms = sum(warm_times) / len(warm_times)

        print(f"\n  Cold (Postgres): {cold_ms:.2f} ms")
        print(f"  Warm  (Redis):   {avg_warm_ms:.2f} ms  (avg of {self.REPEAT} requests)")
        print(f"  Speedup:         {cold_ms / avg_warm_ms:.1f}x")

        assert avg_warm_ms < cold_ms / 2, (
            f"Expected cache hits ({avg_warm_ms:.2f} ms) to be at least 2x "
            f"faster than the cold miss ({cold_ms:.2f} ms)"
        )
