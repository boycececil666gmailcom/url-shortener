@echo off
echo ========================================================
echo Starting URL Shortener in PRODUCTION mode
echo ========================================================
echo Notice: The application will be deployed into your active Kubernetes cluster.
echo Internal APIs, Databases, and Caches will be strictly isolated inside the cluster network.
echo Only the API Gateway is exposed externally via the Ingress controller.
echo.

echo 1. Applying base configurations and secrets...
kubectl apply -f k8s/config.yaml
echo.

echo 2. Applying all Kubernetes manifests...
kubectl apply -R -f k8s/
echo.

echo ========================================================
echo [OK] Production environment is now running!
echo You can access the Gateway at: http://localhost:8000
echo ========================================================
