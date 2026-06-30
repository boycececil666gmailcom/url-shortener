# Auth Service Design

This document details the authentication flow using the **Short-Lived Access Token + Long-Lived Refresh Token** pattern.

## 1. Sign Up / Login & Token Issuance Flow


```mermaid
sequenceDiagram
    participant C as Client (Browser)
    participant G as API Gateway
    participant A as Auth Service
    participant PG as User DB (Postgres)
    participant R as Token DB (Redis)

    C->>G: POST /auth/login {user, pass}
    G->>A: Forward request
    A->>PG: Fetch user record by username
    
    alt User DOES NOT exist (Sign Up)
        A->>A: Hash password with bcrypt (SLOW)
        A->>PG: INSERT INTO users {username, password_hash}
        PG-->>A: Return new user_id
    else User DOES exist (Login)
        PG-->>A: Return existing User Hash
        A->>A: Verify password against Hash (SLOW)
        alt Password Incorrect
            A-->>G: 401 Unauthorized
            G-->>C: 401 Unauthorized (Stop)
        end
    end
    
    A->>A: Generate Access Token (JWT, exp: 15m)
    A->>A: Generate Refresh Token (Opaque string)
    
    A->>R: SET refresh_token:{token} = user_id EX 30d
    
    A-->>G: 200 OK
    Note over A,G: Access Token (JSON body)<br/>Refresh Token (Set-Cookie: HttpOnly)
    G-->>C: 200 OK
```

## 2. Standard API Request & Background Refresh Flow

This diagram shows what happens during a standard API request. If the access token is expired, the client automatically handles it by using the refresh token in the background to get a new access token, and then retries the original request.

```mermaid
sequenceDiagram
    participant C as Client (Browser)
    participant G as API Gateway
    participant S as Shortener Service
    participant A as Auth Service
    participant PG as User DB (Postgres)
    participant R as Token DB (Redis)

    Note over C,S: --- 1. Standard Request Attempt ---
    C->>G: POST /api/v1/shorten
    Note right of C: Header: Authorization: Bearer <JWT>
    
    G->>G: Verify JWT Signature (using RSA Public Key)
    
    alt Token is Valid
        G->>S: Forward to Shortener
        Note right of G: Add Header: X-User-ID: <sub_from_jwt>
        S-->>G: 201 Created
        G-->>C: 201 Created (Success!)
        
    else Token is Expired
        G-->>C: 401 Unauthorized
        
        Note over C,R: --- 2. Automatic Background Refresh ---
        C->>G: POST /auth/refresh
        Note right of C: Cookie: refresh_token=<opaque_string>
        
        G->>A: Forward request
        A->>R: GET refresh_token:{token}
        
        alt Refresh Token Invalid / Expired
            R-->>A: Null
            A-->>G: 401 Unauthorized
            G-->>C: 401 Unauthorized (Must login again)
            
        else Refresh Token Valid
            R-->>A: Return user_id
            A->>PG: Check if user_id still exists/active
            PG-->>A: User is Active
            A->>A: Generate NEW Access Token (JWT, 15m)
            A-->>G: 200 OK {access_token: "..."}
            G-->>C: 200 OK
            
            Note over C,S: --- 3. Retry Original Request ---
            C->>G: POST /api/v1/shorten (retry)
            Note right of C: Header: Authorization: Bearer <NEW_JWT>
            G->>G: Verify NEW JWT Signature
            G->>S: Forward to Shortener
            S-->>G: 201 Created
            G-->>C: 201 Created (Success!)
        end
    end
```

## 3. Logout / Revocation Flow

When the user logs out, we immediately delete the Refresh Token.

```mermaid
sequenceDiagram
    participant C as Client (Browser)
    participant G as API Gateway
    participant A as Auth Service
    participant DB as Auth DB

    C->>G: POST /auth/logout
    Note right of C: Cookie: refresh_token=<opaque_string>
    
    G->>A: Forward request
    A->>DB: DELETE refresh_token WHERE token = <opaque_string>
    
    A-->>G: 200 OK (Clear Cookie)
    G-->>C: 200 OK (User logged out)
    
    Note over C,DB: The user's Access Token might still work<br/>for up to 15 minutes (ghost window), but<br/>they cannot refresh it anymore.
```
