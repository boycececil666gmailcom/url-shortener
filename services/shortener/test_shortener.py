import httpx
import uuid
import pytest

BASE_URL = "http://localhost:8001"

@pytest.fixture(scope="session")
def client():
    with httpx.Client(base_url=BASE_URL, timeout=10.0, follow_redirects=False) as c:
        yield c

@pytest.fixture(scope="module")
def sample_url_data(client):
    url = f"https://example.com/long/path/{uuid.uuid4()}"
    resp = client.post("/shorten", json={"long_url": url})
    assert resp.status_code == 201
    return resp.json()["short_url"], url

def test_shorten_returns_201(client):
    url = f"https://example.com/long/path/{uuid.uuid4()}"
    resp = client.post("/shorten", json={"long_url": url})
    assert resp.status_code == 201
    body = resp.json()
    assert "short_url" in body
    assert body["long_url"] == url

def test_get_url_returns_200(client, sample_url_data):
    short_url, long_url = sample_url_data
    resp = client.get(f"/urls/{short_url}")
    assert resp.status_code == 200
    assert resp.json()["long_url"] == long_url

def test_redirect_returns_302(client, sample_url_data):
    short_url, long_url = sample_url_data
    resp = client.get(f"/r/{short_url}")
    assert resp.status_code == 302
    assert resp.headers["location"] == long_url
