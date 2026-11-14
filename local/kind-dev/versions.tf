terraform {
  required_version = ">= 1.10.0"

  backend "pg" {
    schema_name = "local_kind_dev"
  }

  required_providers {
    kind       = { source = "tehcyx/kind", version = "~> 0.13" }
    kubernetes = { source = "hashicorp/kubernetes", version = "~> 3.0" }
  }
}
