variable "cluster_name" {
  description = "Nome do cluster spoke."
  type        = string
  default     = "kind-dev"
}

variable "http_host_port" {
  description = "Porta do host para o Istio ingress (HTTP): http://sample.localtest.me:<porta>."
  type        = number
  default     = 28080
}

variable "https_host_port" {
  description = "Porta do host para o Istio ingress (HTTPS)."
  type        = number
  default     = 28443
}

variable "cluster_labels" {
  description = "Contrato com os ApplicationSets do platform-gitops."
  type        = map(string)
  default = {
    cloud     = "kind"
    env       = "dev"
    role      = "spoke"
    mesh      = "istio"
    workloads = "enabled"
  }
}
