variable "cluster_name" {
  description = "Nome do cluster hub."
  type        = string
  default     = "mgmt"
}

variable "gitops_repo_url" {
  description = "Repo que a root app observa."
  type        = string
  default     = "https://github.com/patrickcmartins/platform-gitops.git"
}

variable "gitops_revision" {
  description = "Branch/tag do platform-gitops."
  type        = string
  default     = "main"
}

variable "cluster_labels" {
  description = "Labels do hub para os ApplicationSets. mesh=istio instala Istio aqui também (+RAM)."
  type        = map(string)
  default = {
    cloud     = "kind"
    env       = "mgmt"
    role      = "hub"
    mesh      = "none"
    workloads = "disabled"
  }
}
