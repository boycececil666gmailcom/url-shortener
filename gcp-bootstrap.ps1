$ErrorActionPreference = "Stop"

# Configuration variables
$PROJECT_ID = "test-project-501302"
$CLUSTER_NAME = "url-shortener-cluster"
$REGION = "asia-northeast1"
$NAMESPACE = "url-shortener"

# Individual service tags
$GATEWAY_TAG = "v0.0.1"
$AUTH_TAG = "v0.0.1"
$SHORTENER_TAG = "v0.0.1"

$REGISTRY = "$REGION-docker.pkg.dev/$PROJECT_ID/url-shortener"

# Start logging all script output to bootstrap.log
Start-Transcript -Path "bootstrap.log" -Append

Write-Output "=== Bootstrapping Infrastructure for URL Shortener on GKE ==="

# 1. Ensure correct project is set
Write-Output "Setting gcloud project to $PROJECT_ID..."
gcloud config set project $PROJECT_ID

# 2. Build and Push Docker Images to google artifact registry
Write-Output "Authenticating Docker with Artifact Registry..."
gcloud auth configure-docker "$REGION-docker.pkg.dev" --quiet

Write-Output "Building and pushing service images..."

Write-Output "Building gateway image..."
docker build -t "$REGISTRY/gateway:$GATEWAY_TAG" -f "services/gateway/Dockerfile" .
Write-Output "Pushing gateway image..."
docker push "$REGISTRY/gateway:$GATEWAY_TAG"

Write-Output "Building auth image..."
docker build -t "$REGISTRY/auth:$AUTH_TAG" -f "services/auth/Dockerfile" .
Write-Output "Pushing auth image..."
docker push "$REGISTRY/auth:$AUTH_TAG"

Write-Output "Building shortener image..."
docker build -t "$REGISTRY/shortener:$SHORTENER_TAG" -f "services/shortener/Dockerfile" .
Write-Output "Pushing shortener image..."
docker push "$REGISTRY/shortener:$SHORTENER_TAG"

# 3. Run Terraform to provision GKE Cluster, Namespace, and Helm Operators
Write-Output "Running Terraform to provision GKE and Operators..."
Push-Location terraform-gcp
try {
    terraform init
    if ($LASTEXITCODE -ne 0) { throw "Terraform init failed with exit code $LASTEXITCODE." }
    
    terraform apply -auto-approve `
        -var="project_id=$PROJECT_ID" `
        -var="cluster_name=$CLUSTER_NAME" `
        -var="region=$REGION" `
        -var="namespace=$NAMESPACE"
    if ($LASTEXITCODE -ne 0) { throw "Terraform apply failed with exit code $LASTEXITCODE." }
}
catch {
    Write-Error "Terraform deployment failed: $_"
    throw
}
finally {
    Pop-Location
}


# 4. Authenticate kubectl with the GKE cluster
Write-Output "Fetching credentials for cluster..."
gcloud container clusters get-credentials $CLUSTER_NAME `
    --region=$REGION `
    --project=$PROJECT_ID


# 5. Apply Application Config and DB/Redis Resources
Write-Output "Deploying config, secrets, and database/cache clusters..."
kubectl apply -f k8s-gcp/config.yaml
kubectl apply -f k8s-gcp/auth/db-cluster.yaml
kubectl apply -f k8s-gcp/auth/redis-cluster.yaml
kubectl apply -f k8s-gcp/shortener/db-cluster.yaml
kubectl apply -f k8s-gcp/shortener/redis-cluster.yaml

# 6. Wait for databases to initialize
Write-Output "Waiting for PostgreSQL clusters to initialize..."
while (!(kubectl get pods -n $NAMESPACE -l 'application=spilo,cluster-name=shortener-db,spilo-role=master' -o name 2>$null)) { Start-Sleep 2 }
while (!(kubectl get pods -n $NAMESPACE -l 'application=spilo,cluster-name=auth-db,spilo-role=master' -o name 2>$null)) { Start-Sleep 2 }

kubectl wait -n $NAMESPACE --for=condition=Ready pod -l "application=spilo,cluster-name=shortener-db,spilo-role=master" --timeout=300s
kubectl wait -n $NAMESPACE --for=condition=Ready pod -l "application=spilo,cluster-name=auth-db,spilo-role=master" --timeout=300s

# Create logical databases if they do not exist
Write-Output "Creating logical databases..."
$SHORTENER_DB_POD = (kubectl get pods -n $NAMESPACE -l "application=spilo,cluster-name=shortener-db,spilo-role=master" -o jsonpath="{.items[0].metadata.name}")
kubectl exec -n $NAMESPACE $SHORTENER_DB_POD -c postgres -- psql -U postgres -c "CREATE DATABASE urlshortener;" 2>$null

$AUTH_DB_POD = (kubectl get pods -n $NAMESPACE -l "application=spilo,cluster-name=auth-db,spilo-role=master" -o jsonpath="{.items[0].metadata.name}")
kubectl exec -n $NAMESPACE $AUTH_DB_POD -c postgres -- psql -U postgres -c "CREATE DATABASE auth;" 2>$null


# 7. Apply Application Deployments (Auth, Shortener, Gateway)
Write-Output "Deploying application services..."
kubectl apply -f k8s-gcp/auth/app.yaml
kubectl apply -f k8s-gcp/shortener/app.yaml
kubectl apply -f k8s-gcp/gateway/app.yaml
kubectl apply -f k8s-gcp/gateway/ingress.yaml

Write-Output "Updating deployment images to match script tags..."
kubectl set image deployment/gateway gateway="$REGISTRY/gateway:$GATEWAY_TAG" -n $NAMESPACE
kubectl set image deployment/auth auth="$REGISTRY/auth:$AUTH_TAG" -n $NAMESPACE
kubectl set image deployment/shortener shortener="$REGISTRY/shortener:$SHORTENER_TAG" -n $NAMESPACE

Write-Output "=== Deployment Completed! ==="
Write-Output "Check pods using: kubectl get pods -n $NAMESPACE"
Write-Output "Check gateway service: kubectl get svc gateway -n $NAMESPACE"

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
#  |   3. Run Terraform      | ----> [ GKE Cluster, Namespace, & Operators ]
#  +------------+------------+
#               |
#  +------------v------------+
#  |  4. get-credentials GKE |
#  +------------+------------+
#               |
#  +------------v------------+
#  | 5. Apply Config, DB,    |
#  |     & Redis Clusters    |
#  +------------+------------+
#               |
#  +------------v------------+
#  |  6. Wait for DBs Init   |
#  +------------+------------+
#               |
#  +------------v------------+
#  | 7. Deploy App Services  |
#  |     & Set version tags  |
#  +-------------------------+
################################################################################

Stop-Transcript

