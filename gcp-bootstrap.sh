#!/usr/bin/env bash

# Exit immediately if a command exits with a non-zero status
set -e

# Automatically log stdout and stderr to both the terminal and bootstrap.log
LOG_FILE="bootstrap.log"
exec > >(tee -a "$LOG_FILE") 2>&1

echo "Logging session output to $LOG_FILE"

# Configuration variables
PROJECT_ID="test-project-501302"
CLUSTER_NAME="url-shortener-cluster"
REGION="asia-northeast1"
NAMESPACE="url-shortener"

# Individual service tags
GATEWAY_TAG="v0.0.1"
AUTH_TAG="v0.0.1"
SHORTENER_TAG="v0.0.1"

REGISTRY="$REGION-docker.pkg.dev/$PROJECT_ID/url-shortener"

echo "=== Bootstrapping Infrastructure for URL Shortener on GKE ==="

# 1. Ensure correct project is set
echo "Setting gcloud project to $PROJECT_ID..."
gcloud config set project "$PROJECT_ID"

# 2. Build and Push Docker Images
echo "Authenticating Docker with Artifact Registry..."
gcloud auth configure-docker "$REGION-docker.pkg.dev" --quiet

echo "Building and pushing service images..."

echo "Building gateway image..."
docker build -t "$REGISTRY/gateway:$GATEWAY_TAG" -f "services/gateway/Dockerfile" .
echo "Pushing gateway image..."
docker push "$REGISTRY/gateway:$GATEWAY_TAG"

echo "Building auth image..."
docker build -t "$REGISTRY/auth:$AUTH_TAG" -f "services/auth/Dockerfile" .
echo "Pushing auth image..."
docker push "$REGISTRY/auth:$AUTH_TAG"

echo "Building shortener image..."
docker build -t "$REGISTRY/shortener:$SHORTENER_TAG" -f "services/shortener/Dockerfile" .
echo "Pushing shortener image..."
docker push "$REGISTRY/shortener:$SHORTENER_TAG"

# 3. Enable GKE API
echo "Enabling Container API..."
gcloud services enable container.googleapis.com

# 4. Create GKE Autopilot Cluster
echo "Creating GKE Autopilot Cluster '$CLUSTER_NAME' in '$REGION'..."
gcloud container clusters create-auto "$CLUSTER_NAME" \
    --region="$REGION" \
    --project="$PROJECT_ID"

# 5. Authenticate kubectl with the GKE cluster
echo "Fetching credentials for cluster..."
gcloud container clusters get-credentials "$CLUSTER_NAME" \
    --region="$REGION" \
    --project="$PROJECT_ID"

# 6. Create Namespace
echo "Creating namespace '$NAMESPACE'..."
kubectl create namespace "$NAMESPACE" || echo "Namespace already exists"

# 7. Install Zalando Postgres Operator
echo "Installing Zalando Postgres Operator via Helm..."
helm repo add postgres-operator-charts https://opensource.zalando.com/postgres-operator/charts/postgres-operator
helm repo update
helm install postgres-operator postgres-operator-charts/postgres-operator \
    --namespace "$NAMESPACE"

# 8. Install Spotahome Redis Failover Operator
echo "Installing Spotahome Redis Failover Operator..."
kubectl apply -f https://raw.githubusercontent.com/spotahome/redis-operator/master/manifests/schema.yaml
kubectl apply -f https://raw.githubusercontent.com/spotahome/redis-operator/master/manifests/operator.yaml

# 9. Wait for Operators to be ready
echo "Waiting for operators to be ready..."
kubectl rollout status deployment/postgres-operator -n "$NAMESPACE" --timeout=600s
kubectl rollout status deployment/redis-operator -n default --timeout=600s # Standard deployment namespace for redis operator YAML

# 10. Apply Application Config and DB/Redis Resources
echo "Deploying config, secrets, and database/cache clusters..."
kubectl apply -f k8s-gcp/config.yaml
kubectl apply -f k8s-gcp/auth/db-cluster.yaml
kubectl apply -f k8s-gcp/auth/redis-cluster.yaml
kubectl apply -f k8s-gcp/shortener/db-cluster.yaml
kubectl apply -f k8s-gcp/shortener/redis-cluster.yaml

# 11. Wait for databases to initialize
echo "Waiting for PostgreSQL clusters to initialize (this might take a few minutes)..."
echo "You can check progress using: kubectl get postgresql -n $NAMESPACE"

# 12. Apply Application Deployments (Auth, Shortener, Gateway)
echo "Deploying application services..."
kubectl apply -f k8s-gcp/auth/app.yaml
kubectl apply -f k8s-gcp/shortener/app.yaml
kubectl apply -f k8s-gcp/gateway/app.yaml
kubectl apply -f k8s-gcp/gateway/ingress.yaml

echo "Updating deployment images to match script tags..."
kubectl set image deployment/gateway gateway="$REGISTRY/gateway:$GATEWAY_TAG" -n "$NAMESPACE"
kubectl set image deployment/auth auth="$REGISTRY/auth:$AUTH_TAG" -n "$NAMESPACE"
kubectl set image deployment/shortener shortener="$REGISTRY/shortener:$SHORTENER_TAG" -n "$NAMESPACE"

echo "=== Deployment Completed! ==="
echo "Check pods using: kubectl get pods -n $NAMESPACE"
echo "Check gateway service: kubectl get svc gateway -n $NAMESPACE"

################################################################################
# Logic Flow Diagram:
#
#  +-------------------------+
#  |   1. gcloud Project     |
#  +------------+------------+
#               |
#  +------------v------------+
#  | 2. Docker Build & Push  | ----> [ Google Artifact Registry ]
#  +------------+------------+
#               |
#  +------------v------------+
#  |    3. Enable GKE API    |
#  +------------+------------+
#               |
#  +------------v------------+
#  | 4. Create GKE Cluster   |
#  +------------+------------+
#               |
#  +------------v------------+
#  |  5. get-credentials GKE |
#  +------------+------------+
#               |
#  +------------v------------+
#  |  6. Create Namespace    |
#  +------------+------------+
#               |
#  +------------v------------+
#  | 7. Install Helm pg-op   |
#  +------------+------------+
#               |
#  +------------v------------+
#  | 8. Install redis-op     |
#  +------------+------------+
#               |
#  +------------v------------+
#  | 9. Wait Operators Ready |
#  +------------+------------+
#               |
#  +------------v------------+
#  | 10. Apply Config, DB,   |
#  |     & Redis Clusters    |
#  +------------+------------+
#               |
#  +------------v------------+
#  |  11. Wait for DBs Init  |
#  +------------+------------+
#               |
#  +------------v------------+
#  | 12. Deploy App Services |
#  |     & Set version tags  |
#  +-------------------------+
################################################################################

