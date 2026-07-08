import pytest
import requests
import uuid
import time
import os

# Base URL for the API Gateway (e.g. Docker Compose, port-forward, or GKE Ingress)
GATEWAY_URL = os.environ.get("GATEWAY_URL", "http://localhost:8000")

def test_gateway_health():
    """Verify that the gateway is up and running."""
    response = requests.get(f"{GATEWAY_URL}/health")
    assert response.status_code == 200

class TestFullUserJourney:
    """
    Stateful E2E Test Journey.
    """
    
    # Store state between tests
    session = requests.Session() # Use a session to automatically handle cookies (like the refresh token)
    user = f"testuser_{uuid.uuid4()}"
    password = "testpassword"
    access_token = None
    short_url_id = None
    long_url = f"https://example.com/e2e-{uuid.uuid4()}"

    # ==========================================
    # 1. AUTHENTICATION RELATED
    # ==========================================

    def test_01_create_account_and_login(self):
        """Create an account (or login) and get the initial JWT."""
        response = self.session.post(
            f"{GATEWAY_URL}/auth/login",
            json={"user": self.user, "password": self.password}
        )
        assert response.status_code == 200, f"Login failed: {response.text}"
        
        data = response.json()
        assert "access_token" in data, f"Response missing access_token: {data}"
        
        # Save token for future steps
        self.__class__.access_token = data["access_token"]
        
        # The refresh_token should have been set as an HttpOnly cookie
        assert "refresh_token" in self.session.cookies.get_dict(), "No refresh_token cookie found"

    def test_02_verify_jwt_works(self):
        """Test if the JWT works by hitting a protected endpoint without it, then with it."""
        # 1. Without token -> Should fail
        resp_unauth = requests.post(f"{GATEWAY_URL}/api/v1/shorten", json={"long_url": self.long_url})
        assert resp_unauth.status_code == 401, f"Expected 401, got {resp_unauth.status_code}: {resp_unauth.text}"
        
        # 2. With token -> Should work
        headers = {"Authorization": f"Bearer {self.access_token}"}
        resp_auth = requests.post(f"{GATEWAY_URL}/api/v1/shorten", json={"long_url": self.long_url}, headers=headers)
        assert resp_auth.status_code == 201, f"Expected 201, got {resp_auth.status_code}: {resp_auth.text}"
        
        # Save the short URL for the shortener tests later
        self.__class__.short_url_id = resp_auth.json()["short_url"]

    def test_02b_initial_analytics_empty(self):
        """Verify that the analytics service starts with 0 redirects."""
        headers = {"Authorization": f"Bearer {self.access_token}"}
        stats_url = f"{GATEWAY_URL}/api/v1/analytics/stats"
        try:
            response = requests.get(stats_url, headers=headers)
            # If the analytics service is not deployed (e.g. k8s / GCP), we can skip this check
            if response.status_code == 500 or response.status_code == 502:
                pytest.skip("Analytics service is not available in this environment")
            
            assert response.status_code == 200, f"Expected 200, got {response.status_code}: {response.text}"
            data = response.json()
            assert data.get("total_redirects") == 0, f"Expected 0 redirects, got: {data}"
            assert data.get("redirects_by_short_url") == {}, f"Expected empty redirects dictionary, got: {data}"
        except requests.RequestException:
            pytest.skip("Analytics service is unreachable in this environment")

    def test_03_reissue_jwt(self):
        """Test if we can successfully reissue the JWT using the refresh token cookie."""
        # Sleep for 1 second to ensure the new JWT gets a different 'iat' (Issued At) timestamp
        time.sleep(1)
        # The session automatically sends the refresh_token cookie we got in step 1
        response = self.session.post(f"{GATEWAY_URL}/auth/refresh")
        assert response.status_code == 200, f"Refresh failed: {response.text}"
        
        data = response.json()
        assert "access_token" in data, f"Response missing access_token: {data}"
        
        # The new access token should be different from the old one
        assert data["access_token"] != self.access_token, "New access token is identical to old one"
        
        # Update our token to the new one for future requests
        self.__class__.access_token = data["access_token"]

    # ==========================================
    # 2. SHORTENER RELATED (this part use the account from the auth related tests)
    # ==========================================

    def test_04_create_new_url(self):
        """Use the re-issued account token to create another new URL."""
        headers = {"Authorization": f"Bearer {self.access_token}"}
        new_long_url = f"https://example.com/another-{uuid.uuid4()}"
        
        response = requests.post(
            f"{GATEWAY_URL}/api/v1/shorten", 
            json={"long_url": new_long_url}, 
            headers=headers
        )
        assert response.status_code == 201, f"Create failed: {response.text}"
        data = response.json()
        assert data["long_url"] == new_long_url, f"long_url mismatch: {data}"
        assert "short_url" in data, f"Missing short_url: {data}"

    def test_05_retrieve_long_url(self):
        """Retrieve the original long URL using the short one we created in step 2."""
        headers = {"Authorization": f"Bearer {self.access_token}"}
        
        response = requests.get(f"{GATEWAY_URL}/api/v1/urls/{self.short_url_id}", headers=headers)
        assert response.status_code == 200, f"Retrieve failed: {response.text}"
        
        data = response.json()
        assert data["long_url"] == self.long_url, f"long_url mismatch: {data}"
        assert data["short_url"] == self.short_url_id, f"short_url mismatch: {data}"

    def test_06_redirect_and_analytics(self):
        """Test redirecting via short URL and verifying analytics tracks it via Kafka."""
        headers = {"Authorization": f"Bearer {self.access_token}"}
        stats_url = f"{GATEWAY_URL}/api/v1/analytics/stats"

        # 1. Fetch current stats (handling case where service is booting or empty)
        try:
            initial_resp = requests.get(stats_url, headers=headers)
            # If the analytics service is not deployed (e.g. k8s / GCP), we can skip this check
            if initial_resp.status_code == 500 or initial_resp.status_code == 502:
                pytest.skip("Analytics service is not available in this environment")
            assert initial_resp.status_code == 200, f"Failed to get initial stats: {initial_resp.text}"
            initial_stats = initial_resp.json()
            initial_redirects = initial_stats.get("total_redirects", 0)
            initial_count_for_url = initial_stats.get("redirects_by_short_url", {}).get(str(self.short_url_id), 0)
        except requests.RequestException:
            pytest.skip("Analytics service is unreachable in this environment")
        except Exception as e:
            pytest.fail(f"Could not connect to analytics service via gateway: {e}")

        # 2. Hit redirect endpoint (does not require auth)
        redirect_resp = requests.get(f"{GATEWAY_URL}/r/{self.short_url_id}", allow_redirects=False)
        assert redirect_resp.status_code == 302, f"Expected 302, got {redirect_resp.status_code}"
        assert redirect_resp.headers.get("Location") == self.long_url

        # 3. Wait a moment for Kafka async event delivery and consumption
        time.sleep(2)

        # 4. Fetch updated stats
        updated_resp = requests.get(stats_url, headers=headers)
        assert updated_resp.status_code == 200, f"Failed to get updated stats: {updated_resp.text}"
        updated_stats = updated_resp.json()

        # 5. Assert counts increased
        assert updated_stats.get("total_redirects", 0) == initial_redirects + 1
        assert updated_stats.get("redirects_by_short_url", {}).get(str(self.short_url_id), 0) == initial_count_for_url + 1

    # ==========================================
    # 3. CLEANUP / LOGOUT
    # ==========================================

    def test_07_logout(self):
        """Test the deleting/logout endpoint to invalidate the session."""
        # This should clear the refresh_token cookie
        response = self.session.post(f"{GATEWAY_URL}/auth/logout")
        assert response.status_code == 200, f"Logout failed: {response.text}"
        
        # Verify the cookie has been deleted or invalidated
        cookies = self.session.cookies.get_dict()
        assert "refresh_token" not in cookies or cookies["refresh_token"] in ('""', ''), f"Refresh token cookie still present: {cookies}"
