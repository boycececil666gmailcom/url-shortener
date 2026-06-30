import httpx
import uuid
import pytest

BASE_URL = "http://localhost:8000"

@pytest.fixture(scope="session")
def client():
    with httpx.Client(base_url=BASE_URL, timeout=10.0, follow_redirects=False) as c:
        yield c

def test_gateway_auth_and_shorten(client):
    user = f"test_{uuid.uuid4().hex[:8]}"
    pwd = "password123"
    
    # 1. Login to get token
    resp = client.post("/auth/login", json={"user": user, "password": pwd})
    assert resp.status_code == 200
    token = resp.json()["access_token"]
    
    # 2. Shorten URL using token
    headers = {"Authorization": f"Bearer {token}"}
    resp = client.post("/api/v1/shorten", json={"long_url": "https://gateway-test.com"}, headers=headers)
    assert resp.status_code == 201
    short_url = resp.json()["short_url"]
    
    # 3. Lookup using token
    resp = client.get(f"/api/v1/urls/{short_url}", headers=headers)
    assert resp.status_code == 200
    
    # 4. Access without token fails
    resp = client.post("/api/v1/shorten", json={"long_url": "https://gateway-test.com/fail"})
    assert resp.status_code == 401
