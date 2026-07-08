output "kubernetes_cluster_name" {
  value       = google_container_cluster.gke.name
  description = "GKE Cluster Name"
}

output "kubernetes_cluster_endpoint" {
  value       = google_container_cluster.gke.endpoint
  description = "GKE Cluster Endpoint"
}

output "gcloud_get_credentials_command" {
  value       = "gcloud container clusters get-credentials ${google_container_cluster.gke.name} --region ${var.region} --project ${var.project_id}"
  description = "Command to authenticate kubectl locally to this cluster"
}
