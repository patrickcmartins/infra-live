variable "domain" {
  description = "Zona pai, delegada pelo registrador do domínio (registros NS lá apontando para os name servers do output)."
  type        = string
  default     = "lab.neosix.me"
}

variable "environments" {
  description = "Uma zona filha por ambiente: <env>.<domain>. Cada cluster só tem permissão de escrita na sua."
  type        = list(string)
  default     = ["stg", "prod"]
}
