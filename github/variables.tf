variable "owner" {
  description = "Dono dos repositórios (usuário ou organização)."
  type        = string
  default     = "patrickcmartins"
}

variable "reviewers" {
  description = "IDs numéricos dos usuários que aprovam deploy em produção (gh api users/<login> -q .id)."
  type        = list(number)
  default     = [14917330] # patrickcmartins
}

variable "prevent_self_review" {
  description = <<-EOT
    Quem dispara o deploy não pode aprová-lo (separação de funções, SOX/SOC 2).
    false no lab porque só existe UMA pessoa: com true, ninguém conseguiria aprovar.
  EOT
  type        = bool
  default     = false
}

variable "auto_deploy_stg" {
  description = "Liga o CD do sample-app para stg. Só ative depois de criar o secret DEPLOY_REPO_TOKEN no environment staging."
  type        = bool
  default     = false
}

# Checks obrigatórios por repo (nomes exatos dos jobs no GitHub Actions).
variable "required_checks" {
  description = "Checks que precisam passar para o merge na main, por repositório."
  type        = map(list(string))
  default = {
    terraform-modules   = ["terraform / fmt", "terraform / security"]
    terraform-workflows = ["actionlint", "fixtures"]
    atlantis-server     = ["policies"]
    # atlantis/apply obrigatório = PR só entra depois de aplicado (main = o que está no ar).
    infra-live        = ["terraform / fmt", "terraform / security", "env-parity", "atlantis/apply"]
    platform-gitops   = ["render-and-validate"]
    sample-app        = ["test"]
    sample-app-deploy = ["validate"]
  }
}
