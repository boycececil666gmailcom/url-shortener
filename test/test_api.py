"""
Integration tests for the URL Shortener API.

Requires the Docker Compose stack to be running:
    docker compose up -d

Run with:
    pytest test/ -v
"""

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
        assert "short_code" in body
        assert "long_url" in body
        assert "created_at" in body

    def test_shorten_short_code_is_integer(self, client):
        """short_code should be a positive integer."""
        response = client.post("/api/v1/shorten", json={"long_url": self.SAMPLE_URL})
        short_code = response.json()["short_code"]
        assert isinstance(short_code, int)
        assert short_code > 0

    def test_shorten_idempotent(self, client):
        """Submitting the same URL twice should return the same short_code."""
        r1 = client.post("/api/v1/shorten", json={"long_url": self.SAMPLE_URL})
        r2 = client.post("/api/v1/shorten", json={"long_url": self.SAMPLE_URL})
        assert r1.json()["short_code"] == r2.json()["short_code"]

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
    def short_code(self, client):
        """Create a short URL once and reuse its code across lookup tests."""
        response = client.post("/api/v1/shorten", json={"long_url": self.LOOKUP_URL})
        assert response.status_code == 201
        return response.json()["short_code"]

    def test_lookup_returns_200(self, client, short_code):
        """GET /api/v1/urls/{short_code} should return HTTP 200."""
        response = client.get(f"/api/v1/urls/{short_code}")
        assert response.status_code == 200

    def test_lookup_response_shape(self, client, short_code):
        """Lookup response should contain short_code, long_url, and created_at."""
        body = client.get(f"/api/v1/urls/{short_code}").json()
        assert "short_code" in body
        assert "long_url" in body
        assert "created_at" in body

    def test_lookup_long_url_matches(self, client, short_code):
        """Returned long_url should match the originally submitted URL."""
        body = client.get(f"/api/v1/urls/{short_code}").json()
        assert body["long_url"] == self.LOOKUP_URL

    def test_lookup_nonexistent_code_returns_404(self, client):
        """GET with a short_code that doesn't exist should return HTTP 404."""
        response = client.get("/api/v1/urls/999999")
        assert response.status_code == 404


# ── Redirect (GET /r/{short_code}) ───────────────────────────────────────────

class TestRedirect:
    REDIRECT_URL = "https://www.redirect-test.com/destination"

    @pytest.fixture(scope="class")
    def short_code(self, client):
        """Create a short URL once and reuse its code across redirect tests."""
        response = client.post("/api/v1/shorten", json={"long_url": self.REDIRECT_URL})
        assert response.status_code == 201
        return response.json()["short_code"]

    def test_redirect_follows_to_correct_destination(self, client, short_code):
        """GET /r/{short_code} should ultimately resolve to the original URL."""
        response = client.get(f"/r/{short_code}", follow_redirects=True)
        assert str(response.url) == self.REDIRECT_URL

    def test_redirect_status_is_302(self, client, short_code):
        """The initial response before following should be an HTTP 302."""
        response = client.get(f"/r/{short_code}", follow_redirects=False)
        assert response.status_code == 302

    def test_redirect_location_header(self, client, short_code):
        """Location header should point to the original long URL."""
        response = client.get(f"/r/{short_code}", follow_redirects=False)
        assert response.headers["location"] == self.REDIRECT_URL

    def test_redirect_nonexistent_code_returns_404(self, client):
        """GET /r/{short_code} with an unknown code should return HTTP 404."""
        response = client.get("/r/999999", follow_redirects=False)
        assert response.status_code == 404
