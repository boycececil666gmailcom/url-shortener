import httpx
import uuid
import pytest

BASE_URL = "http://localhost:8002"

@pytest.fixture(scope="session")
def client():
    with httpx.Client(base_url=BASE_URL, timeout=10.0, follow_redirects=False) as c:
        yield c

def test_login_and_validate(client):
    user = f"test_{uuid.uuid4().hex[:8]}"
    pwd = "password123"
    # 1. Login
    resp = client.post("/auth/login", json={"user": user, "password": pwd})
    assert resp.status_code == 200
    token = resp.json()["access_token"]
    
    # 2. Validate
    resp = client.get("/auth/validate", headers={"Authorization": f"Bearer {token}"})
    assert resp.status_code == 200

def test_refresh_token(client):
    user = f"test_{uuid.uuid4().hex[:8]}"
    pwd = "password123"
    # Login will set the refresh_token cookie
    resp = client.post("/auth/login", json={"user": user, "password": pwd})
    assert resp.status_code == 200
    
    # Refresh to get a new access token
    resp2 = client.post("/auth/refresh")
    assert resp2.status_code == 200
    assert "access_token" in resp2.json()

def test_logout(client):
    user = f"test_{uuid.uuid4().hex[:8]}"
    pwd = "password123"
    resp = client.post("/auth/login", json={"user": user, "password": pwd})
    assert resp.status_code == 200
    
    resp2 = client.post("/auth/logout")
    assert resp2.status_code == 200
    
    # Refresh should fail now
    resp3 = client.post("/auth/refresh")
    assert resp3.status_code == 401
