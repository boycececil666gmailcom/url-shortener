import pytest
import requests
import uuid
import time

# Base URL for the API Gateway as exposed by docker-compose.yml
GATEWAY_URL = "http://localhost:8000"

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
        
    # ==========================================
    # 3. CLEANUP / LOGOUT
    # ==========================================

    def test_06_logout(self):
        """Test the deleting/logout endpoint to invalidate the session."""
        # This should clear the refresh_token cookie
        response = self.session.post(f"{GATEWAY_URL}/auth/logout")
        assert response.status_code == 200, f"Logout failed: {response.text}"
        
        # Verify the cookie has been deleted or invalidated
        cookies = self.session.cookies.get_dict()
        assert "refresh_token" not in cookies or cookies["refresh_token"] in ('""', ''), f"Refresh token cookie still present: {cookies}"
