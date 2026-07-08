#!/usr/bin/env bash

# SCRIPT_DIR resolves the folder containing this script, ensuring paths are absolute and correct
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "========================================================"
echo "Starting URL Shortener in LOCAL DOCKER COMPOSE mode (SH)"
echo "========================================================"
echo

# 1. Check if Docker daemon is running
echo "[1/4] Checking if Docker daemon is running..."
if ! docker info >/dev/null 2>&1; then
    echo "[ERROR] Docker is not running or not installed!"
    echo "Please start Docker Desktop and try again."
    exit 1
fi
echo "[OK] Docker daemon is running."
echo

# 2. Check if host ports are available (to avoid container start collisions)
echo "[2/4] Checking host-forwarded port availability..."
PORTS_IN_USE=0

# Ports mapping dictionary (Associative Array)
declare -A SERVICES_PORTS=(
    ["Gateway"]="8000"
    ["Shortener"]="8001"
    ["Auth"]="8002"
    ["Shortener_DB"]="5433"
    ["Auth_DB"]="5434"
    ["Shortener_Redis"]="6380"
    ["Auth_Redis"]="6381"
    ["Analytics"]="8003"
    ["Kafka"]="9092"
)

# Loop and check if any ports are already occupied on the host using bash virtual sockets
for name in "${!SERVICES_PORTS[@]}"; do
    port="${SERVICES_PORTS[$name]}"
    if (echo > /dev/tcp/127.0.0.1/"$port") >/dev/null 2>&1; then
        echo "[ERROR] Host port $port ($name) is already in use by another process!"
        PORTS_IN_USE=1
    fi
done

if [ "$PORTS_IN_USE" -eq 1 ]; then
    echo
    echo "[ERROR] One or more required host ports are already occupied."
    echo "Please stop any conflicting services and rerun this script."
    exit 1
fi
echo "[OK] All required host ports are available."
echo

# 3. Start Docker Compose services
echo "[3/4] Starting Docker Compose services..."
docker compose -f "$SCRIPT_DIR/docker-compose.yml" -f "$SCRIPT_DIR/docker-compose.dev.yml" up --build -d
if [ $? -ne 0 ]; then
    echo "[ERROR] Failed to start Docker Compose services!"
    exit 1
fi
echo

# 4. Verify that containers are running and healthy
echo "[4/4] Verifying that services are healthy..."
echo "Waiting up to 30 seconds for all services to become healthy..."

TIMEOUT=30
ELAPSED=0

while [ "$ELAPSED" -lt "$TIMEOUT" ]; do
    ALL_HEALTHY=1
    for name in "${!SERVICES_PORTS[@]}"; do
        port="${SERVICES_PORTS[$name]}"
        if ! (echo > /dev/tcp/127.0.0.1/"$port") >/dev/null 2>&1; then
            ALL_HEALTHY=0
            break
        fi
    done

    if [ "$ALL_HEALTHY" -eq 1 ]; then
        echo
        echo "========================================================"
        echo "[OK] Docker Compose environment is healthy and running!"
        echo "========================================================"
        echo "Gateway URL:   http://localhost:8000"
        echo "Shortener API: http://localhost:8001"
        echo "Auth API:      http://localhost:8002"
        echo
        echo "Database / Cache Host Ports (Exposed in DEV):"
        echo " - Shortener DB:    5433"
        echo " - Auth DB:         5434"
        echo " - Shortener Redis: 6380"
        echo " - Auth Redis:      6381"
        echo "========================================================"
        exit 0
    fi

    sleep 3
    ELAPSED=$((ELAPSED + 3))
    echo "Services not ready yet. Waiting 3 seconds before retrying (${ELAPSED}s/${TIMEOUT}s)..."
done

echo
echo "[WARNING] Not all services became accessible within $TIMEOUT seconds."
echo "Please run 'docker compose -f $SCRIPT_DIR/docker-compose.yml -f $SCRIPT_DIR/docker-compose.dev.yml ps' to check status."
exit 1
