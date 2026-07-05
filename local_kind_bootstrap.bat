@echo off
echo ========================================================
echo Starting URL Shortener in PRODUCTION mode
echo ========================================================
echo Notice: The application will be deployed into your active Kubernetes cluster.
echo Internal APIs, Databases, and Caches will be strictly isolated inside the cluster network.
echo Only the API Gateway is exposed externally via the Ingress controller.
echo.

echo 1. Installing Kubernetes Operators (Postgres and Redis)...
kubectl apply --server-side -k "github.com/zalando/postgres-operator/manifests?ref=v1.15.1"
kubectl apply --server-side -f https://raw.githubusercontent.com/spotahome/redis-operator/v1.2.4/manifests/databases.spotahome.com_redisfailovers.yaml
kubectl apply -f https://raw.githubusercontent.com/spotahome/redis-operator/v1.2.4/example/operator/all-redis-operator-resources.yaml
echo.

echo Waiting for Custom Resource Definitions to be established...
kubectl wait --for=condition=established crd/postgresqls.acid.zalan.do --timeout=60s
kubectl wait --for=condition=established crd/redisfailovers.databases.spotahome.com --timeout=60s
echo.

echo 2. Applying base configurations and secrets...
kubectl apply -f k8s/config.yaml
echo.

echo 3. Applying all Kubernetes manifests...
kubectl apply -R -f k8s/
echo.

echo ========================================================
echo [OK] Production environment is now running!
echo You can access the Gateway at: http://localhost:8000
echo ========================================================
