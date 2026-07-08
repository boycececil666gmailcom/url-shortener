# ==============================================================================
# GCP APIs
# ==============================================================================

# Enable GKE Container API
resource "google_project_service" "container" {
  service            = "container.googleapis.com"
  disable_on_destroy = false
}

# ==============================================================================
# GKE Autopilot Cluster
# ==============================================================================

resource "google_container_cluster" "gke" {
  name             = var.cluster_name
  location         = var.region
  enable_autopilot = true
  depends_on       = [google_project_service.container]
}

# ==============================================================================
# Kubernetes Resources
# ==============================================================================


# Create Application Namespace
resource "kubernetes_namespace" "app_namespace" {
  metadata {
    name = var.namespace
  }
}

# Install Zalando Postgres Operator via Helm
resource "helm_release" "postgres_operator" {
  name       = "postgres-operator"
  repository = "https://opensource.zalando.com/postgres-operator/charts/postgres-operator"
  chart      = "postgres-operator"
  namespace  = kubernetes_namespace.app_namespace.metadata[0].name

  # Wait for deployment to be ready
  wait = true
}

# Install Spotahome Redis Failover Operator via Helm
resource "helm_release" "redis_operator" {
  name       = "redis-operator"
  repository = "https://spotahome.github.io/redis-operator"
  chart      = "redis-operator"
  version    = "3.2.9"
  namespace  = "default" # Deploy to default namespace to match operator behavior

  # Wait for deployment to be ready
  wait = true
}
