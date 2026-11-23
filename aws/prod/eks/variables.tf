variable "region" {
  description = "Região AWS."
  type        = string
  default     = "us-east-2"
}

variable "owner" {
  description = "Tag Owner."
  type        = string
  default     = "patrickcmartins"
}

variable "environment" {
  description = "Nome do ambiente (stg, prod): tags, labels e nome do cluster derivam daqui."
  type        = string
  validation {
    condition     = contains(["stg", "prod"], var.environment)
    error_message = "environment deve ser stg ou prod."
  }
}

variable "cluster_name" {
  description = "Nome do cluster (também o nome no Argo CD e o diretório envs/ no sample-app-deploy)."
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR da VPC. Diferente por ambiente: permite peering/Transit Gateway no futuro sem conflito."
  type        = string
}

variable "public_access_cidrs" {
  description = "Quem acessa a API. Coloque o SEU IP/32 (curl ifconfig.me)."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "admin_role_arn" {
  description = "Role SSO dos humanos admin (kubectl). null = só o deployer."
  type        = string
  default     = "arn:aws:iam::716128129853:role/managed/AccountFullAccessRole"
}


variable "cluster_labels" {
  description = "Contrato com os ApplicationSets (quais addons e workloads o cluster recebe)."
  type        = map(string)
}
