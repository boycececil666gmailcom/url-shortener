@echo off
echo ========================================================
echo 1. Checking if containers are mapped to the hosting machine
echo ========================================================
setlocal enabledelayedexpansion

:: Check all 7 services (Gateway, Auth, Shortener, 2x Postgres, 2x Redis)
for %%i in (Gateway:8000 Shortener:8001 Auth:8002 Shortener_DB:5433 Auth_DB:5434 Shortener_Redis:6380 Auth_Redis:6381) do (
    for /F "tokens=1,2 delims=:" %%a in ("%%i") do (
        powershell -Command "try { $tcp = New-Object System.Net.Sockets.TcpClient('localhost', %%b); $tcp.Close(); exit 0 } catch { exit 1 }"
        IF !ERRORLEVEL! NEQ 0 (
            echo [ERROR] %%a is not accessible on localhost:%%b.
            echo The containers are either not running, or not mapped to the host.
            echo Please start the environment with the development override by running:
            echo docker compose -f docker-compose.yml -f docker-compose.dev.yml up -d
            exit /b 1
        )
    )
)

echo [OK] All 7 containers are successfully mapped and accessible!
echo.
echo ========================================================
echo 2. Flushing databases and caches
echo ========================================================
echo Flushing Shortener PostgreSQL...
docker compose -f docker-compose.yml -f docker-compose.dev.yml exec -T shortener-db psql -U postgres -d urlshortener -c "TRUNCATE TABLE urls RESTART IDENTITY CASCADE;"

echo Flushing Auth PostgreSQL...
docker compose -f docker-compose.yml -f docker-compose.dev.yml exec -T auth-db psql -U postgres -d auth -c "TRUNCATE TABLE users RESTART IDENTITY CASCADE;"

echo Flushing Shortener Redis...
docker compose -f docker-compose.yml -f docker-compose.dev.yml exec -T shortener-redis redis-cli FLUSHALL

echo Flushing Auth Redis...
docker compose -f docker-compose.yml -f docker-compose.dev.yml exec -T auth-redis redis-cli FLUSHALL

