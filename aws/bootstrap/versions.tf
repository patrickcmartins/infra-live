terraform {
  required_version = ">= 1.10.0"

  # 1º apply: state local (o bucket ainda não existe — ovo e galinha).
  # Depois descomente o bloco abaixo e rode: terraform init -migrate-state
  #
  backend "s3" {
    bucket       = "patrickcmartins-tfstate-lab-use2"
    key          = "aws/bootstrap/terraform.tfstate"
    region       = "us-east-2"
    encrypt      = true
    use_lockfile = true
  }

  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 6.0" }
  }
}

# Credencial vem do ambiente (AWS_PROFILE=<seu SSO admin>), nunca do código.
provider "aws" {
  region = var.region
  default_tags {
    tags = {
      Owner       = var.owner
      Environment = "shared"
      ManagedBy   = "terraform"
      Repo        = "infra-live/aws/bootstrap"
    }
  }
}
