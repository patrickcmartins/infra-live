output "environments" {
  description = "Environments gerenciados por este stack."
  value = {
    "sample-app/staging"           = github_repository_environment.app_staging.environment
    "sample-app-deploy/production" = github_repository_environment.deploy_production.environment
  }
}
