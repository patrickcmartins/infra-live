output "state_bucket" {
  description = "Bucket de state."
  value       = aws_s3_bucket.tfstate.bucket
}

output "deployer_role_arn" {
  description = "Vai no secrets/aws/config do atlantis-server (profile lab-deployer)."
  value       = aws_iam_role.deployer.arn
}

output "gha_readonly_role_arn" {
  description = "Vai no secret AWS_READONLY_ROLE_ARN do infra-live (drift detection)."
  value       = module.github_oidc.role_arns["gha-infra-live-readonly"]
}

output "atlantis_user" {
  description = "Crie a key manualmente (fora do state): aws iam create-access-key --user-name atlantis-local"
  value       = aws_iam_user.atlantis.name
}
