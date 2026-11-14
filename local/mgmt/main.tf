# Cluster de gerenciamento (hub): roda o Argo CD que gerencia TODOS os clusters.
module "cluster" {
  source = "git::https://github.com/patrickcmartins/terraform-modules.git//modules/kind-cluster?ref=v0.1.0"
  name   = var.cluster_name
}

# Providers configurados a partir de um recurso do mesmo stack: ok para kind no lab.
# Em produção, separe "cluster" e "conteúdo do cluster" em stacks diferentes.
provider "helm" {
  kubernetes = {
    host                   = module.cluster.endpoint
    cluster_ca_certificate = module.cluster.cluster_ca_certificate
    client_certificate     = module.cluster.client_certificate
    client_key             = module.cluster.client_key
  }
}

provider "kubernetes" {
  host                   = module.cluster.endpoint
  cluster_ca_certificate = module.cluster.cluster_ca_certificate
  client_certificate     = module.cluster.client_certificate
  client_key             = module.cluster.client_key
}

module "argocd" {
  source = "git::https://github.com/patrickcmartins/terraform-modules.git//modules/argocd-bootstrap?ref=v0.1.0"

  root_app = {
    repo_url = var.gitops_repo_url
    revision = var.gitops_revision
    path     = "bootstrap/hub"
  }
}

# O próprio hub também é um "cluster" para o Argo CD, com labels para os ApplicationSets.
module "self_registration" {
  source = "git::https://github.com/patrickcmartins/terraform-modules.git//modules/argocd-cluster-secret?ref=v0.1.0"

  name               = var.cluster_name
  server             = "https://kubernetes.default.svc"
  ca_data            = module.cluster.cluster_ca_certificate
  client_certificate = module.cluster.client_certificate
  client_key         = module.cluster.client_key
  labels             = var.cluster_labels

  depends_on = [module.argocd]
}
