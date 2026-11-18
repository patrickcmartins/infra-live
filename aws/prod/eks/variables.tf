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

variable "cluster_name" {
  description = "Nome do cluster (também o nome no Argo CD e o diretório envs/ no sample-app-deploy)."
  type        = string
  default     = "eks-prod"
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
  description = "Contrato com os ApplicationSets."
  type        = map(string)
  default = {
    cloud     = "aws"
    env       = "prod"
    role      = "spoke"
    mesh      = "istio"
    workloads = "enabled"
  }
}
