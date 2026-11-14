output "cluster_name" {
  description = "aws eks update-kubeconfig --name <isto> --region us-east-1"
  value       = module.eks.cluster_name
}

output "cluster_endpoint" {
  description = "API do EKS."
  value       = module.eks.cluster_endpoint
}
