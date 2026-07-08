#!/usr/bin/env bash

# Resolve the absolute path of the script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "========================================================"
echo "1. Bootstrapping Local Docker Compose Environment"
echo "========================================================"
if ! bash "$SCRIPT_DIR/../deployment_manifest/local-docker-compose/local-docker-compose-bootstrap.sh"; then
    echo "[ERROR] Failed to bootstrap Local Docker Compose environment!"
    exit 1
fi
echo

echo "========================================================"
echo "2. Flushing databases and caches"
echo "========================================================"
# Change directory to where the compose file is located, so docker compose knows the context
cd "$SCRIPT_DIR/../deployment_manifest/local-docker-compose"

echo "Flushing Shortener PostgreSQL..."
docker compose exec -T shortener-db psql -U postgres -d urlshortener -c "TRUNCATE TABLE urls RESTART IDENTITY CASCADE;"

echo "Flushing Auth PostgreSQL..."
docker compose exec -T auth-db psql -U postgres -d auth -c "TRUNCATE TABLE users RESTART IDENTITY CASCADE;"

echo "Flushing Shortener Redis..."
docker compose exec -T shortener-redis redis-cli FLUSHALL

echo "Flushing Auth Redis..."
docker compose exec -T auth-redis redis-cli FLUSHALL

echo "Restarting Analytics service to clear in-memory stats..."
docker compose restart analytics
echo

echo "========================================================"
echo "3. Running E2E Tests"
echo "========================================================"
python -m pytest "$SCRIPT_DIR/e2eTest/test_shortener_e2e.py"
