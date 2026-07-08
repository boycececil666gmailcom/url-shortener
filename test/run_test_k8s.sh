#!/usr/bin/env bash

# Resolve the absolute path of the script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PORT_FORWARD_PID=""

# Helper function to get pod name based on label selector
get_pod_name() {
    local selector=$1
    kubectl get pods -n url-shortener -l "$selector" -o jsonpath="{.items[0].metadata.name}" 2>/dev/null
}

# Cleanup function to kill port forward process on exit
cleanup() {
    if [ -n "$PORT_FORWARD_PID" ]; then
        echo "Stopping Port-Forward tunnel (PID: $PORT_FORWARD_PID)..."
        kill "$PORT_FORWARD_PID" 2>/dev/null
    fi
}
trap cleanup EXIT

echo "========================================================"
echo "1. Checking Port 8000 Availability"
echo "========================================================"
if (echo > /dev/tcp/127.0.0.1/8000) >/dev/null 2>&1; then
    echo "[ERROR] Port 8000 is already in use by another process!"
    echo "Please manually stop whatever is occupying port 8000 before running this script."
    exit 1
fi
echo "[OK] Port 8000 is free."
echo

echo "========================================================"
echo "1.5 Building Local Docker Images"
echo "========================================================"
echo "Building Shortener Service..."
docker build -t url-shortener-shortener:latest -f "$SCRIPT_DIR/../services/shortener/Dockerfile" "$SCRIPT_DIR/.."
echo "Building Auth Service..."
docker build -t url-shortener-auth:latest -f "$SCRIPT_DIR/../services/auth/Dockerfile" "$SCRIPT_DIR/.."
echo "Building Gateway Service..."
docker build -t url-shortener-gateway:latest -f "$SCRIPT_DIR/../services/gateway/Dockerfile" "$SCRIPT_DIR/.."
echo

echo "========================================================"
echo "2. Starting Kubernetes Network"
echo "========================================================"
echo "Installing Kubernetes Operators (Postgres and Redis)..."
kubectl apply --server-side -k "github.com/zalando/postgres-operator/manifests?ref=v1.15.1"
kubectl apply --server-side -f https://raw.githubusercontent.com/spotahome/redis-operator/v1.2.4/manifests/databases.spotahome.com_redisfailovers.yaml
kubectl apply -f https://raw.githubusercontent.com/spotahome/redis-operator/v1.2.4/example/operator/all-redis-operator-resources.yaml
echo

echo "Waiting for Custom Resource Definitions to be established..."
kubectl wait --for=condition=established crd/postgresqls.acid.zalan.do --timeout=60s
kubectl wait --for=condition=established crd/redisfailovers.databases.spotahome.com --timeout=60s
echo

kubectl apply -f "$SCRIPT_DIR/../deployment_manifest/k8s/config.yaml"
kubectl apply -R -f "$SCRIPT_DIR/../deployment_manifest/k8s"
echo

echo "Waiting for Database and Cache Master pods to be created..."
while [ -z "$(get_pod_name "application=spilo,cluster-name=shortener-db,spilo-role=master")" ]; do sleep 2; done
while [ -z "$(get_pod_name "application=spilo,cluster-name=auth-db,spilo-role=master")" ]; do sleep 2; done
while [ -z "$(get_pod_name "redisfailovers-role=master,redisfailovers.databases.spotahome.com/name=shortener-redis")" ]; do sleep 2; done
while [ -z "$(get_pod_name "redisfailovers-role=master,redisfailovers.databases.spotahome.com/name=auth-redis")" ]; do sleep 2; done

echo "Waiting for Database and Cache Master nodes to be ready..."
kubectl wait -n url-shortener --for=condition=Ready pod -l "application=spilo,cluster-name=shortener-db,spilo-role=master" --timeout=300s
kubectl wait -n url-shortener --for=condition=Ready pod -l "application=spilo,cluster-name=auth-db,spilo-role=master" --timeout=300s
kubectl wait -n url-shortener --for=condition=Ready pod -l "redisfailovers-role=master,redisfailovers.databases.spotahome.com/name=shortener-redis" --timeout=300s
kubectl wait -n url-shortener --for=condition=Ready pod -l "redisfailovers-role=master,redisfailovers.databases.spotahome.com/name=auth-redis" --timeout=300s
echo

echo "Waiting for Auth and Shortener applications to be ready..."
kubectl wait -n url-shortener --for=condition=available deployment/auth --timeout=120s
kubectl wait -n url-shortener --for=condition=available deployment/shortener --timeout=120s
echo

echo "========================================================"
echo "3. Flushing databases and caches via Kubernetes"
echo "========================================================"

echo "Flushing Shortener PostgreSQL..."
SHORTENER_DB_POD=$(get_pod_name "application=spilo,cluster-name=shortener-db,spilo-role=master")
kubectl exec -n url-shortener "$SHORTENER_DB_POD" -- psql -U postgres -c "CREATE DATABASE urlshortener;" 2>/dev/null
kubectl exec -n url-shortener "$SHORTENER_DB_POD" -- psql -U postgres -d urlshortener -c "TRUNCATE TABLE urls RESTART IDENTITY CASCADE;"

echo "Flushing Auth PostgreSQL..."
AUTH_DB_POD=$(get_pod_name "application=spilo,cluster-name=auth-db,spilo-role=master")
kubectl exec -n url-shortener "$AUTH_DB_POD" -- psql -U postgres -c "CREATE DATABASE auth;" 2>/dev/null
kubectl exec -n url-shortener "$AUTH_DB_POD" -- psql -U postgres -d auth -c "TRUNCATE TABLE users RESTART IDENTITY CASCADE;"

echo "Flushing Shortener Redis..."
SHORTENER_REDIS_POD=$(get_pod_name "redisfailovers-role=master,redisfailovers.databases.spotahome.com/name=shortener-redis")
kubectl exec -n url-shortener "$SHORTENER_REDIS_POD" -- redis-cli FLUSHALL

echo "Flushing Auth Redis..."
AUTH_REDIS_POD=$(get_pod_name "redisfailovers-role=master,redisfailovers.databases.spotahome.com/name=auth-redis")
kubectl exec -n url-shortener "$AUTH_REDIS_POD" -- redis-cli FLUSHALL
echo

echo "========================================================"
echo "4. Starting Port-Forward and Running Tests"
echo "========================================================"
echo "Tunneling Kubernetes Gateway to localhost:8000 in background..."
kubectl port-forward -n url-shortener svc/gateway 8000:8000 >/dev/null 2>&1 &
PORT_FORWARD_PID=$!
sleep 3

echo "Running E2E Tests..."
python -m pytest "$SCRIPT_DIR/e2eTest/test_shortener_e2e.py"
TEST_EXIT_CODE=$?

exit $TEST_EXIT_CODE
