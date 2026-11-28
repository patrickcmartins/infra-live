module "eks" {
  source = "git::https://github.com/patrickcmartins/terraform-modules.git//modules/aws-eks?ref=v0.2.0"

  name                = var.cluster_name
  cost_profile        = "lab"
  vpc_cidr            = var.vpc_cidr
  instance_types      = ["t3.xlarge", "t3a.xlarge"] # Istio + OTel + Prometheus/Tempo/Loki
  webhook_ports       = [15017]                     # istiod: injeção de sidecar e validação
  public_access_cidrs = var.public_access_cidrs

  access_entries = var.admin_role_arn == null ? {} : {
    admin = {
      principal_arn = var.admin_role_arn
      policy_associations = {
        admin = {
          policy_arn   = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
          access_scope = { type = "cluster" }
        }
      }
    }
  }
}

# Auth por exec: token NOVO a cada chamada. O token estático (data aws_eks_cluster_auth)
# é gerado no início do run e expira em 15 min; criar o cluster leva mais que isso, e os
# recursos de Kubernetes do mesmo apply falhavam com "Unauthorized".
provider "kubernetes" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", module.eks.cluster_name, "--region", var.region]
  }
}

# Identidade dedicada do Argo CD neste cluster: revogável sem afetar mais nada.
resource "kubernetes_service_account_v1" "argocd_manager" {
  metadata {
    name      = "argocd-manager"
    namespace = "kube-system"
  }
}

resource "kubernetes_cluster_role_binding_v1" "argocd_manager" {
  metadata {
    name = "argocd-manager"
  }
  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = "cluster-admin" # addons (Istio) precisam de CRDs/webhooks
  }
  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account_v1.argocd_manager.metadata[0].name
    namespace = "kube-system"
  }
}

resource "kubernetes_secret_v1" "argocd_manager_token" {
  metadata {
    name      = "argocd-manager-token"
    namespace = "kube-system"
    annotations = {
      "kubernetes.io/service-account.name" = kubernetes_service_account_v1.argocd_manager.metadata[0].name
    }
  }
  type                           = "kubernetes.io/service-account-token"
  wait_for_service_account_token = true
}

# ---------------------------------------------------------------- registro no hub
data "terraform_remote_state" "mgmt" {
  backend = "pg"
  config = {
    schema_name = "local_mgmt"
  }
}

provider "kubernetes" {
  alias                  = "hub"
  host                   = data.terraform_remote_state.mgmt.outputs.hub_endpoint
  cluster_ca_certificate = data.terraform_remote_state.mgmt.outputs.hub_ca_certificate
  client_certificate     = data.terraform_remote_state.mgmt.outputs.hub_client_certificate
  client_key             = data.terraform_remote_state.mgmt.outputs.hub_client_key
}

module "registration" {
  source    = "git::https://github.com/patrickcmartins/terraform-modules.git//modules/argocd-cluster-secret?ref=v0.2.0"
  providers = { kubernetes = kubernetes.hub }

  name         = var.cluster_name
  server       = module.eks.cluster_endpoint
  ca_data      = base64decode(module.eks.cluster_certificate_authority_data)
  bearer_token = kubernetes_secret_v1.argocd_manager_token.data["token"]
  labels       = var.cluster_labels
}
