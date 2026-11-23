terraform {
  required_version = ">= 1.10.0"

  backend "s3" {
    bucket       = "patrickcmartins-tfstate-lab-use2"
    key          = "aws/stg/eks/terraform.tfstate"
    region       = "us-east-2"
    encrypt      = true
    use_lockfile = true # lock nativo no S3 (sem DynamoDB) desde o TF 1.10
  }

  required_providers {
    aws        = { source = "hashicorp/aws", version = "~> 6.0" }
    kubernetes = { source = "hashicorp/kubernetes", version = "~> 3.0" }
  }
}

provider "aws" {
  region = var.region
  default_tags {
    tags = {
      Owner       = var.owner
      Environment = var.environment
      ManagedBy   = "terraform"
      Repo        = "infra-live/aws/${var.environment}/eks"
    }
  }
}
