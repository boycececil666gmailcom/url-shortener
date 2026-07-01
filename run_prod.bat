@echo off
echo ========================================================
echo Starting URL Shortener in PRODUCTION mode
echo ========================================================
echo Notice: Only the API Gateway (port 8000) will be exposed to the host machine.
echo Internal APIs (ports 8001, 8002), Databases (5433, 5434), and Caches (6380, 6381) 
echo will be strictly isolated inside the Docker network.
echo.

echo 1. Tearing down any existing development containers...
docker compose down
echo.

echo 2. Starting production containers...
docker compose -f docker-compose.yml up -d --build
echo.

echo ========================================================
echo [OK] Production environment is now running!
echo You can access the Gateway at: http://localhost:8000
echo ========================================================
