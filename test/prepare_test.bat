@echo off
echo ========================================================
echo 1. Checking Port 8000 Availability
echo ========================================================
powershell -Command "try { $listener = [System.Net.Sockets.TcpListener]::Create(8000); $listener.Start(); $listener.Stop(); exit 0 } catch { exit 1 }"
IF %ERRORLEVEL% NEQ 0 (
    echo [ERROR] Port 8000 is already in use by another process!
    echo Please manually stop whatever is occupying port 8000 ^(e.g., Docker Compose, kubectl port-forward, or another app^) before running this script.
    exit /b 1
)

echo.
echo ========================================================
echo 2. Starting Docker Compose Environment
echo ========================================================
docker compose -f ../docker-compose.yml -f ../docker-compose.dev.yml up -d

echo.
echo ========================================================
echo 3. Checking if containers are ready and mapped to the hosting machine
echo ========================================================
setlocal enabledelayedexpansion

:: Check all 7 services (Gateway, Auth, Shortener, 2x Postgres, 2x Redis)
for %%i in (Gateway:8000 Shortener:8001 Auth:8002 Shortener_DB:5433 Auth_DB:5434 Shortener_Redis:6380 Auth_Redis:6381) do (
    for /F "tokens=1,2 delims=:" %%a in ("%%i") do (
        powershell -Command "try { $tcp = New-Object System.Net.Sockets.TcpClient('localhost', %%b); $tcp.Close(); exit 0 } catch { exit 1 }"
        IF !ERRORLEVEL! NEQ 0 (
            echo [ERROR] %%a is not accessible on localhost:%%b.
            echo The containers failed to start or map correctly. Please check Docker logs.
            exit /b 1
        )
    )
)

echo [OK] All 7 containers are successfully mapped and accessible!
echo.
echo ========================================================
echo 4. Flushing databases and caches
echo ========================================================
echo Flushing Shortener PostgreSQL...
docker compose -f ../docker-compose.yml -f ../docker-compose.dev.yml exec -T shortener-db psql -U postgres -d urlshortener -c "TRUNCATE TABLE urls RESTART IDENTITY CASCADE;"

echo Flushing Auth PostgreSQL...
docker compose -f ../docker-compose.yml -f ../docker-compose.dev.yml exec -T auth-db psql -U postgres -d auth -c "TRUNCATE TABLE users RESTART IDENTITY CASCADE;"

echo Flushing Shortener Redis Cluster...
docker compose -f ../docker-compose.yml -f ../docker-compose.dev.yml exec -T shortener-redis-1 redis-cli FLUSHALL
docker compose -f ../docker-compose.yml -f ../docker-compose.dev.yml exec -T shortener-redis-2 redis-cli FLUSHALL
docker compose -f ../docker-compose.yml -f ../docker-compose.dev.yml exec -T shortener-redis-3 redis-cli FLUSHALL

echo Flushing Auth Redis Cluster...
docker compose -f ../docker-compose.yml -f ../docker-compose.dev.yml exec -T auth-redis-1 redis-cli FLUSHALL
docker compose -f ../docker-compose.yml -f ../docker-compose.dev.yml exec -T auth-redis-2 redis-cli FLUSHALL
docker compose -f ../docker-compose.yml -f ../docker-compose.dev.yml exec -T auth-redis-3 redis-cli FLUSHALL
