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
echo 2. Starting Kubernetes Network
echo ========================================================
kubectl apply -f ../k8s/config.yaml
kubectl apply -R -f ../k8s/
:: Give the pods a moment to initialize before flushing
timeout /t 10 /nobreak

echo.
echo ========================================================
echo 3. Flushing databases and caches via Kubernetes
echo ========================================================

echo Flushing Shortener PostgreSQL...
:: Find the primary Postgres pod (Zalando operator labels the primary)
for /f "tokens=*" %%i in ('kubectl get pods -n url-shortener -l "application=spilo,cluster-name=shortener-db,spilo-role=master" -o jsonpath^="{.items[0].metadata.name}"') do set SHORTENER_DB_POD=%%i
kubectl exec -n url-shortener %SHORTENER_DB_POD% -- psql -U postgres -d urlshortener -c "TRUNCATE TABLE urls RESTART IDENTITY CASCADE;"

echo Flushing Auth PostgreSQL...
for /f "tokens=*" %%i in ('kubectl get pods -n url-shortener -l "application=spilo,cluster-name=auth-db,spilo-role=master" -o jsonpath^="{.items[0].metadata.name}"') do set AUTH_DB_POD=%%i
kubectl exec -n url-shortener %AUTH_DB_POD% -- psql -U postgres -d auth -c "TRUNCATE TABLE users RESTART IDENTITY CASCADE;"

echo Flushing Shortener Redis...
:: Find the Redis master node (Spotahome operator labels the master)
for /f "tokens=*" %%i in ('kubectl get pods -n url-shortener -l "redis-role=master,redisfailover=shortener-redis" -o jsonpath^="{.items[0].metadata.name}"') do set SHORTENER_REDIS_POD=%%i
kubectl exec -n url-shortener %SHORTENER_REDIS_POD% -- redis-cli FLUSHALL

echo Flushing Auth Redis...
for /f "tokens=*" %%i in ('kubectl get pods -n url-shortener -l "redis-role=master,redisfailover=auth-redis" -o jsonpath^="{.items[0].metadata.name}"') do set AUTH_REDIS_POD=%%i
kubectl exec -n url-shortener %AUTH_REDIS_POD% -- redis-cli FLUSHALL

echo.
echo ========================================================
echo 4. Starting Port-Forward for E2E Tests
echo ========================================================
echo Tunneling Kubernetes Gateway to localhost:8000...
echo Leave this running and execute `pytest` in another terminal!
kubectl port-forward -n url-shortener svc/gateway 8000:8000
