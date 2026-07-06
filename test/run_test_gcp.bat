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
echo [Checking Namespace]
kubectl get ns url-shortener
if %ERRORLEVEL% neq 0 (
    echo [ERROR] namespace 'url-shortener' not found in cluster.
    exit /b 1
)

echo.
echo [Checking Services]
kubectl get svc -n url-shortener
if %ERRORLEVEL% neq 0 (
    echo [ERROR] Failed to fetch services in namespace 'url-shortener'.
    exit /b 1
)

echo.
echo ========================================================
echo 3. Checking and Flushing GKE databases and caches
echo ========================================================

echo --- Phase 1: Verifying Existence ---

echo Finding shortener database master pod...
call :GetPodName "application=spilo,cluster-name=shortener-db,spilo-role=master" SHORTENER_DB_POD

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
echo [OK] Shortener database exists.

echo Finding auth database master pod...
call :GetPodName "application=spilo,cluster-name=auth-db,spilo-role=master" AUTH_DB_POD

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
echo [OK] Auth database exists.

echo Finding Shortener Redis master pod...
call :GetPodName "redisfailovers-role=master,redisfailovers.databases.spotahome.com/name=shortener-redis" SHORTENER_REDIS_POD

if "%SHORTENER_REDIS_POD%"=="" (
    echo [ERROR] Could not find shortener-redis master pod!
    exit /b 1
)
echo [OK] Shortener Redis master pod exists.

echo Finding Auth Redis master pod...
call :GetPodName "redisfailovers-role=master,redisfailovers.databases.spotahome.com/name=auth-redis" AUTH_REDIS_POD

if "%AUTH_REDIS_POD%"=="" (
    echo [ERROR] Could not find auth-redis master pod!
    exit /b 1
)
echo [OK] Auth Redis master pod exists.
echo [OK] All databases and caches verified successfully.

echo.
echo --- Phase 2: Flushing Data ---

echo Flushing GKE Shortener PostgreSQL table urls...
kubectl exec -n url-shortener %SHORTENER_DB_POD% -c postgres -- psql -U postgres -d urlshortener -c "DO $$ BEGIN IF EXISTS (SELECT FROM pg_tables WHERE schemaname = 'public' AND tablename = 'urls') THEN TRUNCATE TABLE urls RESTART IDENTITY CASCADE; END IF; END $$;"

echo Flushing GKE Auth PostgreSQL table users...
kubectl exec -n url-shortener %AUTH_DB_POD% -c postgres -- psql -U postgres -d auth -c "DO $$ BEGIN IF EXISTS (SELECT FROM pg_tables WHERE schemaname = 'public' AND tablename = 'users') THEN TRUNCATE TABLE users RESTART IDENTITY CASCADE; END IF; END $$;"

echo Flushing GKE Shortener Redis...
kubectl exec -n url-shortener %SHORTENER_REDIS_POD% -- redis-cli FLUSHALL

echo Flushing GKE Auth Redis...
kubectl exec -n url-shortener %AUTH_REDIS_POD% -- redis-cli FLUSHALL

echo.
echo --- Phase 3: Verifying Flush ---

set URLS_COUNT=0
for /f "tokens=*" %%i in ('kubectl exec -n url-shortener %SHORTENER_DB_POD% -c postgres -- psql -U postgres -d urlshortener -tAc "SELECT count(*) FROM urls;" 2^>nul') do set URLS_COUNT=%%i
if "%URLS_COUNT%" neq "0" (
    echo [ERROR] Shortener urls table was not successfully flushed! Found %URLS_COUNT% records.
    exit /b 1
)
echo [OK] Shortener database verified: 0 urls records.

set USERS_COUNT=0
for /f "tokens=*" %%i in ('kubectl exec -n url-shortener %AUTH_DB_POD% -c postgres -- psql -U postgres -d auth -tAc "SELECT count(*) FROM users;" 2^>nul') do set USERS_COUNT=%%i
if "%USERS_COUNT%" neq "0" (
    echo [ERROR] Auth users table was not successfully flushed! Found %USERS_COUNT% records.
    exit /b 1
)
echo [OK] Auth database verified: 0 users records.

set SHORTENER_REDIS_SIZE=0
for /f "tokens=*" %%i in ('kubectl exec -n url-shortener %SHORTENER_REDIS_POD% -- redis-cli DBSIZE 2^>nul') do set SHORTENER_REDIS_SIZE=%%i
if "%SHORTENER_REDIS_SIZE%" neq "0" (
    echo [ERROR] Shortener Redis was not successfully flushed! DBSIZE = %SHORTENER_REDIS_SIZE%
    exit /b 1
)
echo [OK] Shortener Redis verified: 0 keys.

set AUTH_REDIS_SIZE=0
for /f "tokens=*" %%i in ('kubectl exec -n url-shortener %AUTH_REDIS_POD% -- redis-cli DBSIZE 2^>nul') do set AUTH_REDIS_SIZE=%%i
if "%AUTH_REDIS_SIZE%" neq "0" (
    echo [ERROR] Auth Redis was not successfully flushed! DBSIZE = %AUTH_REDIS_SIZE%
    exit /b 1
)
echo [OK] Auth Redis verified: 0 keys.

echo [OK] All databases and caches successfully flushed and verified!


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

exit /b %ERRORLEVEL%

:GetPodName
for /f "tokens=*" %%i in ('kubectl get pods -n url-shortener -l "%~1" -o jsonpath^="{.items[0].metadata.name}" 2^>nul') do set %2=%%i
exit /b 0
