# Identidade IAM do AWS Load Balancer Controller, via EKS Pod Identity (ADR 0003).
# Por quê: o gateway do Istio passa a ter um NLB em modo IP (o NLB fala direto com o
# IP do pod, sem NodePort nem salto entre nodes). Quem cria esse NLB é o controller.
#
# A policy é a OFICIAL do controller, sem edição: aws/shared/iam/aws-load-balancer-controller.json
# (docs/install/iam_policy.json da tag v3.6.3, a mesma versão do chart no platform-gitops).
# Atualizar o chart? Atualize este arquivo no mesmo passo.
# Escrita restrita por tag (elbv2.k8s.aws/cluster) onde a API permite.

resource "aws_iam_role" "lb_controller" {
  name               = "${var.cluster_name}-aws-load-balancer-controller"
  assume_role_policy = data.aws_iam_policy_document.pod_identity_trust.json
}

resource "aws_iam_role_policy" "lb_controller" {
  role   = aws_iam_role.lb_controller.id
  policy = file("${path.module}/../../shared/iam/aws-load-balancer-controller.json")
}

resource "aws_eks_pod_identity_association" "lb_controller" {
  cluster_name    = module.eks.cluster_name
  namespace       = "kube-system"
  service_account = "aws-load-balancer-controller"
  role_arn        = aws_iam_role.lb_controller.arn
}
