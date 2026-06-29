# Authentication Service Implementation Plan

## Overview
This document outlines the steps to implement the authentication service based on the provided design documents (auth-flow and schema).

## 1. Database Setup
### PostgreSQL (User DB)
- Create `users` table:
  - `id` (SERIAL PRIMARY KEY)
  - `username` (VARCHAR(50) UNIQUE NOT NULL)
  - `password_hash` (VARCHAR(255) NOT NULL)
  - `created_at` (TIMESTAMPTZ DEFAULT NOW())

### Redis (Token DB)
- Configure Redis connection for storing refresh tokens.
- Key pattern: `refresh_token:{token_string}` -> Value: `user_id`, TTL: 30 days.

## 2. API Endpoints Implementation

### A. POST `/auth/login` (Sign Up / Login)
1. Receive `{user, pass}` from request.
2. Query Postgres for `username`.
3. If user DOES NOT exist (Sign Up):
   - Hash password using `bcrypt`.
   - Insert into `users` table.
4. If user DOES exist (Login):
   - Verify provided password against `password_hash` using `bcrypt`.
   - Return 401 Unauthorized if incorrect.
5. Generate Access Token (JWT, exp: 15m). Include user `id` as `sub` claim.
6. Generate Refresh Token (Opaque string).
7. Store Refresh Token in Redis with 30-day expiration.
8. Return 200 OK with Access Token in JSON body and Refresh Token in `Set-Cookie: HttpOnly`.

### B. POST `/auth/refresh` (Background Refresh)
1. Read Refresh Token from `Cookie: refresh_token=<opaque_string>`.
2. Retrieve `user_id` from Redis using the token as key.
3. If token is invalid or expired (not found in Redis), return 401 Unauthorized.
4. (Optional) Verify user still exists/is active in Postgres.
5. Generate a new Access Token (JWT, exp: 15m).
6. Return 200 OK with the new Access Token in JSON body.

### C. POST `/auth/logout`
1. Read Refresh Token from `Cookie`.
2. Delete the corresponding key from Redis (`DEL refresh_token:<opaque_string>`).
3. Return 200 OK and clear the cookie.
