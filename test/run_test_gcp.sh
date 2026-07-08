#!/usr/bin/env bash

# Resolve the absolute path of the script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Helper function to get pod name based on label selector
get_pod_name() {
    local selector=$1
    kubectl get pods -n url-shortener -l "$selector" -o jsonpath="{.items[0].metadata.name}" 2>/dev/null
}

echo "========================================================"
echo "1. Fetching GKE Cluster Credentials"
echo "========================================================"
gcloud container clusters get-credentials url-shortener-cluster --region=asia-northeast1 --project=test-project-501302
if [ $? -ne 0 ]; then
    echo "[ERROR] Failed to fetch GKE cluster credentials. Please make sure you are logged in to gcloud."
    exit 1
fi
echo

echo "========================================================"
echo "2. Checking GKE Namespace and Services"
echo "========================================================"
echo "[Checking Namespace]"
kubectl get ns url-shortener
if [ $? -ne 0 ]; then
    echo "[ERROR] namespace 'url-shortener' not found in cluster."
    exit 1
fi
echo

echo "[Checking Services]"
kubectl get svc -n url-shortener
if [ $? -ne 0 ]; then
    echo "[ERROR] Failed to fetch services in namespace 'url-shortener'."
    exit 1
fi
echo

echo "========================================================"
echo "3. Checking and Flushing GKE databases and caches"
echo "========================================================"

echo "--- Phase 1: Verifying Existence ---"

echo "Finding shortener database master pod..."
SHORTENER_DB_POD=$(get_pod_name "application=spilo,cluster-name=shortener-db,spilo-role=master")
if [ -z "$SHORTENER_DB_POD" ]; then
    echo "[ERROR] Could not find shortener-db master pod!"
    exit 1
fi

DB_EXISTS=$(kubectl exec -n url-shortener "$SHORTENER_DB_POD" -c postgres -- psql -U postgres -tAc "SELECT 1 FROM pg_database WHERE datname='urlshortener'" 2>/dev/null)
if [ "$DB_EXISTS" != "1" ]; then
    echo "[ERROR] Logical database \"urlshortener\" does not exist! Please run bootstrap or create the database first."
    exit 1
fi
echo "[OK] Shortener database exists."

echo "Finding auth database master pod..."
AUTH_DB_POD=$(get_pod_name "application=spilo,cluster-name=auth-db,spilo-role=master")
if [ -z "$AUTH_DB_POD" ]; then
    echo "[ERROR] Could not find auth-db master pod!"
    exit 1
fi

DB_EXISTS=$(kubectl exec -n url-shortener "$AUTH_DB_POD" -c postgres -- psql -U postgres -tAc "SELECT 1 FROM pg_database WHERE datname='auth'" 2>/dev/null)
if [ "$DB_EXISTS" != "1" ]; then
    echo "[ERROR] Logical database \"auth\" does not exist! Please run bootstrap or create the database first."
    exit 1
fi
echo "[OK] Auth database exists."

echo "Finding Shortener Redis master pod..."
SHORTENER_REDIS_POD=$(get_pod_name "redisfailovers-role=master,redisfailovers.databases.spotahome.com/name=shortener-redis")
if [ -z "$SHORTENER_REDIS_POD" ]; then
    echo "[ERROR] Could not find shortener-redis master pod!"
    exit 1
fi
echo "[OK] Shortener Redis master pod exists."

echo "Finding Auth Redis master pod..."
AUTH_REDIS_POD=$(get_pod_name "redisfailovers-role=master,redisfailovers.databases.spotahome.com/name=auth-redis")
if [ -z "$AUTH_REDIS_POD" ]; then
    echo "[ERROR] Could not find auth-redis master pod!"
    exit 1
fi
echo "[OK] Auth Redis master pod exists."
echo "[OK] All databases and caches verified successfully."
echo

echo "--- Phase 2: Flushing Data ---"

echo "Flushing GKE Shortener PostgreSQL table urls..."
kubectl exec -n url-shortener "$SHORTENER_DB_POD" -c postgres -- psql -U postgres -d urlshortener -c "DO \$\$ BEGIN IF EXISTS (SELECT FROM pg_tables WHERE schemaname = 'public' AND tablename = 'urls') THEN TRUNCATE TABLE urls RESTART IDENTITY CASCADE; END IF; END \$\$;"

echo "Flushing GKE Auth PostgreSQL table users..."
kubectl exec -n url-shortener "$AUTH_DB_POD" -c postgres -- psql -U postgres -d auth -c "DO \$\$ BEGIN IF EXISTS (SELECT FROM pg_tables WHERE schemaname = 'public' AND tablename = 'users') THEN TRUNCATE TABLE users RESTART IDENTITY CASCADE; END IF; END \$\$;"

echo "Flushing GKE Shortener Redis..."
kubectl exec -n url-shortener "$SHORTENER_REDIS_POD" -- redis-cli FLUSHALL

echo "Flushing GKE Auth Redis..."
kubectl exec -n url-shortener "$AUTH_REDIS_POD" -- redis-cli FLUSHALL
echo

echo "--- Phase 3: Verifying Flush ---"

URLS_COUNT=$(kubectl exec -n url-shortener "$SHORTENER_DB_POD" -c postgres -- psql -U postgres -d urlshortener -tAc "SELECT count(*) FROM urls;" 2>/dev/null)
if [ "$URLS_COUNT" != "0" ]; then
    echo "[ERROR] Shortener urls table was not successfully flushed! Found $URLS_COUNT records."
    exit 1
fi
echo "[OK] Shortener database verified: 0 urls records."

USERS_COUNT=$(kubectl exec -n url-shortener "$AUTH_DB_POD" -c postgres -- psql -U postgres -d auth -tAc "SELECT count(*) FROM users;" 2>/dev/null)
if [ "$USERS_COUNT" != "0" ]; then
    echo "[ERROR] Auth users table was not successfully flushed! Found $USERS_COUNT records."
    exit 1
fi
echo "[OK] Auth database verified: 0 users records."

SHORTENER_REDIS_SIZE=$(kubectl exec -n url-shortener "$SHORTENER_REDIS_POD" -- redis-cli DBSIZE 2>/dev/null)
if [ "$SHORTENER_REDIS_SIZE" != "0" ]; then
    echo "[ERROR] Shortener Redis was not successfully flushed! DBSIZE = $SHORTENER_REDIS_SIZE"
    exit 1
fi
echo "[OK] Shortener Redis verified: 0 keys."

AUTH_REDIS_SIZE=$(kubectl exec -n url-shortener "$AUTH_REDIS_POD" -- redis-cli DBSIZE 2>/dev/null)
if [ "$AUTH_REDIS_SIZE" != "0" ]; then
    echo "[ERROR] Auth Redis was not successfully flushed! DBSIZE = $AUTH_REDIS_SIZE"
    exit 1
fi
echo "[OK] Auth Redis verified: 0 keys."
echo "[OK] All databases and caches successfully flushed and verified!"
echo

echo "========================================================"
echo "4. Detecting Ingress IP and Running Tests"
echo "========================================================"
echo "Waiting for GKE Ingress External IP to be allocated..."
echo "(This may take a few minutes if the load balancer was recently created...)"

while true; do
    INGRESS_IP=$(kubectl get ingress gateway-ingress -n url-shortener -o jsonpath="{.status.loadBalancer.ingress[0].ip}" 2>/dev/null)
    if [ -n "$INGRESS_IP" ]; then
        break
    fi
    sleep 5
done

echo
echo "[OK] Cloud Ingress IP detected: $INGRESS_IP"
echo "Running E2E tests directly against GKE cluster at http://$INGRESS_IP..."
echo

export GATEWAY_URL="http://$INGRESS_IP"
python -m pytest "$SCRIPT_DIR/e2eTest/test_shortener_e2e.py"
exit $?
