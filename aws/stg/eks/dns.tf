# Identidades IAM dos addons de DNS e TLS deste cluster, via EKS Pod Identity (ADR 0003):
# nenhuma chave; o pod da ServiceAccount recebe credencial temporária da role.
# Escopo: SÓ a zona do próprio ambiente (<env>.patricktf.neosix.me), lida do stack global de DNS.

data "terraform_remote_state" "dns" {
  backend = "s3"
  config = {
    bucket = "patrickcmartins-tfstate-lab-use2"
    key    = "aws/global/dns/terraform.tfstate"
    region = "us-east-2"
  }
}

locals {
  zone_id  = data.terraform_remote_state.dns.outputs.zone_ids[var.environment]
  zone_arn = "arn:aws:route53:::hostedzone/${local.zone_id}"
}

data "aws_iam_policy_document" "pod_identity_trust" {
  statement {
    principals {
      type        = "Service"
      identifiers = ["pods.eks.amazonaws.com"]
    }
    actions = ["sts:AssumeRole", "sts:TagSession"]
  }
}

# ---------------------------------------------------------------- external-dns
# Cria/atualiza os registros a partir dos hosts dos Gateways do Istio.
data "aws_iam_policy_document" "external_dns" {
  statement {
    actions   = ["route53:ChangeResourceRecordSets", "route53:ListResourceRecordSets", "route53:ListTagsForResources"]
    resources = [local.zone_arn]
  }
  statement {
    actions   = ["route53:ListHostedZones"]
    resources = ["*"] # a API não aceita escopo aqui
  }
}

resource "aws_iam_role" "external_dns" {
  name               = "${var.cluster_name}-external-dns"
  assume_role_policy = data.aws_iam_policy_document.pod_identity_trust.json
}

resource "aws_iam_role_policy" "external_dns" {
  role   = aws_iam_role.external_dns.id
  policy = data.aws_iam_policy_document.external_dns.json
}

resource "aws_eks_pod_identity_association" "external_dns" {
  cluster_name    = module.eks.cluster_name
  namespace       = "external-dns"
  service_account = "external-dns"
  role_arn        = aws_iam_role.external_dns.arn
}

# ---------------------------------------------------------------- cert-manager
# Desafio DNS-01 da Let's Encrypt: cria um TXT _acme-challenge e apaga depois.
# Ainda mais restrito que o external-dns: SÓ registros TXT.
data "aws_iam_policy_document" "cert_manager" {
  statement {
    actions   = ["route53:ChangeResourceRecordSets"]
    resources = [local.zone_arn]
    condition {
      test     = "ForAllValues:StringEquals"
      variable = "route53:ChangeResourceRecordSetsRecordTypes"
      values   = ["TXT"]
    }
  }
  statement {
    actions   = ["route53:ListResourceRecordSets"]
    resources = [local.zone_arn]
  }
  statement {
    actions   = ["route53:GetChange"]
    resources = ["arn:aws:route53:::change/*"]
  }
  statement {
    actions   = ["route53:ListHostedZonesByName"]
    resources = ["*"]
  }
}

resource "aws_iam_role" "cert_manager" {
  name               = "${var.cluster_name}-cert-manager"
  assume_role_policy = data.aws_iam_policy_document.pod_identity_trust.json
}

resource "aws_iam_role_policy" "cert_manager" {
  role   = aws_iam_role.cert_manager.id
  policy = data.aws_iam_policy_document.cert_manager.json
}

resource "aws_eks_pod_identity_association" "cert_manager" {
  cluster_name    = module.eks.cluster_name
  namespace       = "cert-manager"
  service_account = "cert-manager"
  role_arn        = aws_iam_role.cert_manager.arn
}
