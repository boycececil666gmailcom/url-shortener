variable "project_id" {
  type        = string
  description = "The GCP Project ID"
  default     = "test-project-501302"
}

variable "region" {
  type        = string
  description = "The GCP Region for resources"
  default     = "asia-northeast1"
}

variable "cluster_name" {
  type        = string
  description = "The GKE Autopilot Cluster Name"
  default     = "url-shortener-cluster"
}

variable "namespace" {
  type        = string
  description = "The Kubernetes namespace to create"
  default     = "url-shortener"
}
