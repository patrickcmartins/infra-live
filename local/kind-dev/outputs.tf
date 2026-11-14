output "endpoint" {
  description = "API do cluster vista do host."
  value       = module.cluster.endpoint
}

output "argocd_cluster_name" {
  description = "Nome do cluster no Argo CD."
  value       = module.registration.cluster_name
}
