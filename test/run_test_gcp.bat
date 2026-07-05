@echo off
echo ========================================================
echo 1. Fetching GKE Cluster Credentials
echo ========================================================
call gcloud container clusters get-credentials url-shortener-cluster --region=asia-northeast1 --project=test-project-501302
if %ERRORLEVEL% neq 0 (
    echo [ERROR] Failed to fetch GKE cluster credentials. Please make sure you are logged in to gcloud.
    exit /b 1
)

echo.
echo ========================================================
echo 2. Checking GKE Namespace and Services
echo ========================================================
kubectl get ns url-shortener >nul 2>&1
if %ERRORLEVEL% neq 0 (
    echo [ERROR] namespace 'url-shortener' not found in cluster.
    exit /b 1
)

echo.
echo ========================================================
echo 3. Flushing GKE databases and caches
echo ========================================================

echo Finding shortener database master pod...
for /f "tokens=*" %%i in ('kubectl get pods -n url-shortener -l "application=spilo,cluster-name=shortener-db,spilo-role=master" -o jsonpath^="{.items[0].metadata.name}" 2^>nul') do set SHORTENER_DB_POD=%%i

if "%SHORTENER_DB_POD%"=="" (
    echo [ERROR] Could not find shortener-db master pod!
    exit /b 1
)

set DB_EXISTS=
for /f "tokens=*" %%i in ('kubectl exec -n url-shortener %SHORTENER_DB_POD% -c postgres -- psql -U postgres -tAc "SELECT 1 FROM pg_database WHERE datname='urlshortener'" 2^>nul') do set DB_EXISTS=%%i
if "%DB_EXISTS%" neq "1" (
    echo [ERROR] Logical database "urlshortener" does not exist! Please run bootstrap or create the database first.
    exit /b 1
)
echo Flushing GKE Shortener PostgreSQL table urls...
kubectl exec -n url-shortener %SHORTENER_DB_POD% -c postgres -- psql -U postgres -d urlshortener -c "DO $$ BEGIN IF EXISTS (SELECT FROM pg_tables WHERE schemaname = 'public' AND tablename = 'urls') THEN TRUNCATE TABLE urls RESTART IDENTITY CASCADE; END IF; END $$;"

echo Finding auth database master pod...
for /f "tokens=*" %%i in ('kubectl get pods -n url-shortener -l "application=spilo,cluster-name=auth-db,spilo-role=master" -o jsonpath^="{.items[0].metadata.name}" 2^>nul') do set AUTH_DB_POD=%%i

if "%AUTH_DB_POD%"=="" (
    echo [ERROR] Could not find auth-db master pod!
    exit /b 1
)

set DB_EXISTS=
for /f "tokens=*" %%i in ('kubectl exec -n url-shortener %AUTH_DB_POD% -c postgres -- psql -U postgres -tAc "SELECT 1 FROM pg_database WHERE datname='auth'" 2^>nul') do set DB_EXISTS=%%i
if "%DB_EXISTS%" neq "1" (
    echo [ERROR] Logical database "auth" does not exist! Please run bootstrap or create the database first.
    exit /b 1
)
echo Flushing GKE Auth PostgreSQL table users...
kubectl exec -n url-shortener %AUTH_DB_POD% -c postgres -- psql -U postgres -d auth -c "DO $$ BEGIN IF EXISTS (SELECT FROM pg_tables WHERE schemaname = 'public' AND tablename = 'users') THEN TRUNCATE TABLE users RESTART IDENTITY CASCADE; END IF; END $$;"


echo Finding Shortener Redis master pod...
for /f "tokens=*" %%i in ('kubectl get pods -n url-shortener -l "redisfailovers-role=master,redisfailovers.databases.spotahome.com/name=shortener-redis" -o jsonpath^="{.items[0].metadata.name}" 2^>nul') do set SHORTENER_REDIS_POD=%%i

if "%SHORTENER_REDIS_POD%"=="" (
    echo [ERROR] Could not find shortener-redis master pod!
    exit /b 1
)
echo Flushing GKE Shortener Redis...
kubectl exec -n url-shortener %SHORTENER_REDIS_POD% -- redis-cli FLUSHALL

echo Finding Auth Redis master pod...
for /f "tokens=*" %%i in ('kubectl get pods -n url-shortener -l "redisfailovers-role=master,redisfailovers.databases.spotahome.com/name=auth-redis" -o jsonpath^="{.items[0].metadata.name}" 2^>nul') do set AUTH_REDIS_POD=%%i

if "%AUTH_REDIS_POD%"=="" (
    echo [ERROR] Could not find auth-redis master pod!
    exit /b 1
)
echo Flushing GKE Auth Redis...
kubectl exec -n url-shortener %AUTH_REDIS_POD% -- redis-cli FLUSHALL


echo.
echo ========================================================
echo 4. Detecting Ingress IP and Running Tests
echo ========================================================
echo Waiting for GKE Ingress External IP to be allocated...
echo (This may take a few minutes if the load balancer was recently created...)

:wait_loop
set INGRESS_IP=
for /f "tokens=*" %%i in ('kubectl get ingress gateway-ingress -n url-shortener -o jsonpath^="{.status.loadBalancer.ingress[0].ip}" 2^>nul') do set INGRESS_IP=%%i

if "%INGRESS_IP%"=="" (
    timeout /t 5 >nul
    goto wait_loop
)

echo.
echo [OK] Cloud Ingress IP detected: %INGRESS_IP%
echo Running E2E tests directly against GKE cluster at http://%INGRESS_IP%...
echo.

set GATEWAY_URL=http://%INGRESS_IP%
python -m pytest "%~dp0e2eTest\test_shortener_e2e.py"
