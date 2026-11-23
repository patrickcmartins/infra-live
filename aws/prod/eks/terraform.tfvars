# O que difere entre stg e prod mora AQUI (e na chave do state em versions.tf).
# main.tf é idêntico nos dois ambientes; o CI falha se divergir.
environment  = "prod"
cluster_name = "eks-prod"
vpc_cidr     = "10.40.0.0/16"

cluster_labels = {
  cloud         = "aws"
  env           = "prod"
  role          = "spoke"
  mesh          = "istio"
  workloads     = "enabled"
  observability = "enabled"
  messaging     = "enabled"
  dns           = "enabled"
}
