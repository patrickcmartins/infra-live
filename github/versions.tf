terraform {
  required_version = ">= 1.10.0"

  # State no Postgres do atlantis-server (PG_CONN_STR). Não é infra de nuvem, mas é infra:
  # quem pode fazer deploy em prod é uma decisão que merece PR, review e histórico.
  backend "pg" {
    schema_name = "github_config"
  }

  required_providers {
    github = { source = "integrations/github", version = "~> 6.6" }
  }
}

# Token via env GITHUB_TOKEN (nunca no código). Lab: PAT fine-grained só com
# Administration + Environments + Variables nos repos abaixo.
# Mundo ideal: GitHub App (app_auth), com permissões mínimas e token de 1h.
provider "github" {
  owner = var.owner
}
