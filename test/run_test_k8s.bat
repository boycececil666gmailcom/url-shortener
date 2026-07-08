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

echo ========================================================
echo 1.5 Building Local Docker Images
echo ========================================================
echo Building Shortener Service...
docker build -t url-shortener-shortener:latest -f "%~dp0..\services\shortener\Dockerfile" "%~dp0.."
echo Building Auth Service...
docker build -t url-shortener-auth:latest -f "%~dp0..\services\auth\Dockerfile" "%~dp0.."
echo Building Gateway Service...
docker build -t url-shortener-gateway:latest -f "%~dp0..\services\gateway\Dockerfile" "%~dp0.."
echo.

echo ========================================================
echo 2. Starting Kubernetes Network
echo ========================================================
echo Installing Kubernetes Operators (Postgres and Redis)...
kubectl apply --server-side -k "github.com/zalando/postgres-operator/manifests?ref=v1.15.1"
kubectl apply --server-side -f https://raw.githubusercontent.com/spotahome/redis-operator/v1.2.4/manifests/databases.spotahome.com_redisfailovers.yaml
kubectl apply -f https://raw.githubusercontent.com/spotahome/redis-operator/v1.2.4/example/operator/all-redis-operator-resources.yaml
echo.

echo Waiting for Custom Resource Definitions to be established...
kubectl wait --for=condition=established crd/postgresqls.acid.zalan.do --timeout=60s
kubectl wait --for=condition=established crd/redisfailovers.databases.spotahome.com --timeout=60s
echo.

kubectl apply -f "%~dp0..\deployment_manifest\k8s\config.yaml"
kubectl apply -R -f "%~dp0..\deployment_manifest\k8s"

echo.
echo Waiting for Database and Cache Master pods to be created...
powershell -Command "while (!(kubectl get pods -n url-shortener -l 'application=spilo,cluster-name=shortener-db,spilo-role=master' -o name 2>$null)) { Start-Sleep 2 }"
powershell -Command "while (!(kubectl get pods -n url-shortener -l 'application=spilo,cluster-name=auth-db,spilo-role=master' -o name 2>$null)) { Start-Sleep 2 }"
powershell -Command "while (!(kubectl get pods -n url-shortener -l 'redisfailovers-role=master,redisfailovers.databases.spotahome.com/name=shortener-redis' -o name 2>$null)) { Start-Sleep 2 }"
powershell -Command "while (!(kubectl get pods -n url-shortener -l 'redisfailovers-role=master,redisfailovers.databases.spotahome.com/name=auth-redis' -o name 2>$null)) { Start-Sleep 2 }"

echo Waiting for Database and Cache Master nodes to be ready...
kubectl wait -n url-shortener --for=condition=Ready pod -l "application=spilo,cluster-name=shortener-db,spilo-role=master" --timeout=300s
kubectl wait -n url-shortener --for=condition=Ready pod -l "application=spilo,cluster-name=auth-db,spilo-role=master" --timeout=300s
kubectl wait -n url-shortener --for=condition=Ready pod -l "redisfailovers-role=master,redisfailovers.databases.spotahome.com/name=shortener-redis" --timeout=300s
kubectl wait -n url-shortener --for=condition=Ready pod -l "redisfailovers-role=master,redisfailovers.databases.spotahome.com/name=auth-redis" --timeout=300s
echo.

echo Waiting for Auth and Shortener applications to be ready...
kubectl wait -n url-shortener --for=condition=available deployment/auth --timeout=120s
kubectl wait -n url-shortener --for=condition=available deployment/shortener --timeout=120s
echo.

echo ========================================================
echo 3. Flushing databases and caches via Kubernetes
echo ========================================================

echo Flushing Shortener PostgreSQL...
:: Find the primary Postgres pod
for /f "tokens=*" %%i in ('kubectl get pods -n url-shortener -l "application=spilo,cluster-name=shortener-db,spilo-role=master" -o jsonpath^="{.items[0].metadata.name}"') do set SHORTENER_DB_POD=%%i
kubectl exec -n url-shortener %SHORTENER_DB_POD% -- psql -U postgres -c "CREATE DATABASE urlshortener;" 2>nul
kubectl exec -n url-shortener %SHORTENER_DB_POD% -- psql -U postgres -d urlshortener -c "TRUNCATE TABLE urls RESTART IDENTITY CASCADE;"

echo Flushing Auth PostgreSQL...
for /f "tokens=*" %%i in ('kubectl get pods -n url-shortener -l "application=spilo,cluster-name=auth-db,spilo-role=master" -o jsonpath^="{.items[0].metadata.name}"') do set AUTH_DB_POD=%%i
kubectl exec -n url-shortener %AUTH_DB_POD% -- psql -U postgres -c "CREATE DATABASE auth;" 2>nul
kubectl exec -n url-shortener %AUTH_DB_POD% -- psql -U postgres -d auth -c "TRUNCATE TABLE users RESTART IDENTITY CASCADE;"

echo Flushing Shortener Redis...
for /f "tokens=*" %%i in ('kubectl get pods -n url-shortener -l "redisfailovers-role=master,redisfailovers.databases.spotahome.com/name=shortener-redis" -o jsonpath^="{.items[0].metadata.name}"') do set SHORTENER_REDIS_POD=%%i
kubectl exec -n url-shortener %SHORTENER_REDIS_POD% -- redis-cli FLUSHALL

echo Flushing Auth Redis...
for /f "tokens=*" %%i in ('kubectl get pods -n url-shortener -l "redisfailovers-role=master,redisfailovers.databases.spotahome.com/name=auth-redis" -o jsonpath^="{.items[0].metadata.name}"') do set AUTH_REDIS_POD=%%i
kubectl exec -n url-shortener %AUTH_REDIS_POD% -- redis-cli FLUSHALL

echo.
echo ========================================================
echo 4. Starting Port-Forward and Running Tests
echo ========================================================
echo Tunneling Kubernetes Gateway to localhost:8000 in background...
start "kubectl-port-forward" /b kubectl port-forward -n url-shortener svc/gateway 8000:8000
timeout /t 3 >nul

echo Running E2E Tests...
python -m pytest "%~dp0e2eTest\test_shortener_e2e.py"
set TEST_EXIT_CODE=%ERRORLEVEL%

echo.
echo Stopping Port-Forward tunnel...
wmic process where "CommandLine like '%%port-forward%%svc/gateway%%8000:8000%%'" call terminate >nul 2>&1

exit /b %TEST_EXIT_CODE%
