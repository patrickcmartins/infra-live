terraform {
  required_version = ">= 1.10.0"

  # Postgres do atlantis-server. Conexão via env PG_CONN_STR (nunca no código).
  backend "pg" {
    schema_name = "local_mgmt"
  }

  required_providers {
    kind       = { source = "tehcyx/kind", version = "~> 0.13" }
    helm       = { source = "hashicorp/helm", version = "~> 3.3" }
    kubernetes = { source = "hashicorp/kubernetes", version = "~> 3.0" }
  }
}
