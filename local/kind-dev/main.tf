# Spoke "dev": simula uma segunda cloud/datacenter. Recebe Istio + apps via Argo CD do hub.
data "terraform_remote_state" "mgmt" {
  backend = "pg"
  config = {
    schema_name = "local_mgmt"
  }
}

module "cluster" {
  source = "git::https://github.com/patrickcmartins/terraform-modules.git//modules/kind-cluster?ref=v0.1.0"

  name        = var.cluster_name
  node_labels = { "ingress-ready" = "true" }
  port_mappings = [
    { container_port = 30080, host_port = var.http_host_port },
    { container_port = 30443, host_port = var.https_host_port },
  ]
}

provider "kubernetes" {
  alias                  = "hub"
  host                   = data.terraform_remote_state.mgmt.outputs.hub_endpoint
  cluster_ca_certificate = data.terraform_remote_state.mgmt.outputs.hub_ca_certificate
  client_certificate     = data.terraform_remote_state.mgmt.outputs.hub_client_certificate
  client_key             = data.terraform_remote_state.mgmt.outputs.hub_client_key
}

module "registration" {
  source    = "git::https://github.com/patrickcmartins/terraform-modules.git//modules/argocd-cluster-secret?ref=v0.1.0"
  providers = { kubernetes = kubernetes.hub }

  name   = var.cluster_name
  server = module.cluster.internal_endpoint # alcançável pelos pods do hub (rede docker "kind")
  # Lab: cert admin. Produção: ServiceAccount dedicada com RBAC mínimo (como no stack EKS).
  ca_data            = module.cluster.cluster_ca_certificate
  client_certificate = module.cluster.client_certificate
  client_key         = module.cluster.client_key
  labels             = var.cluster_labels
}
