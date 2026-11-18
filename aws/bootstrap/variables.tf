variable "region" {
  description = "Região principal."
  type        = string
  default     = "us-east-2"
}

variable "owner" {
  description = "Tag Owner."
  type        = string
  default     = "patrickcmartins"
}

variable "github_owner" {
  description = "Usuário/org do GitHub."
  type        = string
  default     = "patrickcmartins"
}

variable "state_bucket_name" {
  description = "Bucket de state (nome global; precisa bater com os backends)."
  type        = string
  default     = "patrickcmartins-tfstate-lab-use2"
}

variable "budget_limit_usd" {
  description = "Orçamento mensal; alerta em 50%, 80% e 100% (previsto)."
  type        = number
  default     = 20
}

variable "budget_email" {
  description = "E-mail que recebe os alertas de custo."
  type        = string
}

variable "deployer_trusted_principals" {
  description = "ARNs extras que podem assumir o terraform-deployer (ex.: sua role SSO admin)."
  type        = list(string)
  default     = []
}
