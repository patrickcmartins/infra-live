# O que difere entre stg e prod mora AQUI (e na chave do state em versions.tf).
# main.tf é idêntico nos dois ambientes; o CI falha se divergir.
environment  = "stg"
cluster_name = "eks-stg"
vpc_cidr     = "10.41.0.0/16"

# Paridade com prod: mesmos addons. stg só serve para algo se for igual a prod.
cluster_labels = {
  cloud         = "aws"
  env           = "stg"
  role          = "spoke"
  mesh          = "istio"
  workloads     = "enabled"
  observability = "enabled"
  messaging     = "enabled"
}
