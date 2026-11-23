terraform {
  required_version = ">= 1.10.0"

  backend "s3" {
    bucket       = "patrickcmartins-tfstate-lab-use2"
    key          = "aws/global/dns/terraform.tfstate"
    region       = "us-east-2"
    encrypt      = true
    use_lockfile = true
  }

  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 6.0" }
  }
}

provider "aws" {
  region = "us-east-2" # Route 53 é global; a região só define o endpoint da API
  default_tags {
    tags = {
      Owner       = "patrickcmartins"
      Environment = "global"
      ManagedBy   = "terraform"
      Repo        = "infra-live/aws/global/dns"
    }
  }
}
