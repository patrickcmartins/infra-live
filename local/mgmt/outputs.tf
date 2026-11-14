# Consumidos pelos stacks spoke (terraform_remote_state) para registrar clusters no hub.
output "hub_endpoint" {
  description = "API do hub vista do host/Atlantis."
  value       = module.cluster.endpoint
}

output "hub_ca_certificate" {
  description = "CA do hub (PEM)."
  value       = module.cluster.cluster_ca_certificate
}

output "hub_client_certificate" {
  description = "Cert admin do hub. Sensível: fica no state (por isso o state é protegido)."
  value       = module.cluster.client_certificate
  sensitive   = true
}

output "hub_client_key" {
  description = "Chave admin do hub."
  value       = module.cluster.client_key
  sensitive   = true
}

output "argocd_namespace" {
  description = "Namespace do Argo CD."
  value       = module.argocd.namespace
}
