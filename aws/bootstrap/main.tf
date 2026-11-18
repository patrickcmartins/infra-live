

locals {
  repo = "${var.github_owner}/infra-live"
}

# ---------------------------------------------------------------- state bucket
resource "aws_s3_bucket" "tfstate" {
  bucket = var.state_bucket_name
  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_s3_bucket_versioning" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id
  versioning_configuration {
    status = "Enabled" # rollback de state corrompido
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "aws:kms"
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "tfstate" {
  bucket                  = aws_s3_bucket.tfstate.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id
  rule {
    id     = "expire-old-versions"
    status = "Enabled"
    filter {}
    noncurrent_version_expiration {
      noncurrent_days = 90
    }
  }
}

data "aws_iam_policy_document" "tfstate_tls_only" {
  statement {
    sid     = "DenyInsecureTransport"
    effect  = "Deny"
    actions = ["s3:*"]
    principals {
      type        = "*"
      identifiers = ["*"]
    }
    resources = [aws_s3_bucket.tfstate.arn, "${aws_s3_bucket.tfstate.arn}/*"]
    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_s3_bucket_policy" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id
  policy = data.aws_iam_policy_document.tfstate_tls_only.json
}

# ---------------------------------------------------------------- GitHub OIDC
# GitHub Actions (drift detection, plans read-only) sem NENHUMA access key.
data "aws_iam_policy_document" "state_read" {
  statement {
    actions = ["s3:GetObject", "s3:ListBucket"]
    # ARN montado a partir do nome (conhecido no plan). Usar aws_s3_bucket.tfstate.arn
    # deixa o JSON "unknown" e quebra o for_each do módulo (inline_policy_json != null).
    resources = ["arn:aws:s3:::${var.state_bucket_name}", "arn:aws:s3:::${var.state_bucket_name}/*"]
  }
}

module "github_oidc" {
  source = "git::https://github.com/patrickcmartins/terraform-modules.git//modules/aws-github-oidc?ref=v0.1.0"

  roles = {
    gha-infra-live-readonly = {
      subjects = [
        "repo:${local.repo}:ref:refs/heads/main",
        "repo:${local.repo}:pull_request",
      ]
      managed_policy_arns = ["arn:aws:iam::aws:policy/ReadOnlyAccess"]
      inline_policy_json  = data.aws_iam_policy_document.state_read.json
    }
  }
}

# ---------------------------------------------------------------- Atlantis
# Usuário com UMA permissão: assumir o deployer. A key sozinha não faz nada.
resource "aws_iam_user" "atlantis" {
  name = "atlantis-local"
}

data "aws_iam_policy_document" "atlantis_assume" {
  statement {
    actions   = ["sts:AssumeRole", "sts:TagSession"]
    resources = [aws_iam_role.deployer.arn]
  }
}

resource "aws_iam_user_policy" "atlantis_assume" {
  name   = "assume-deployer"
  user   = aws_iam_user.atlantis.name
  policy = data.aws_iam_policy_document.atlantis_assume.json
}

data "aws_iam_policy_document" "deployer_trust" {
  statement {
    actions = ["sts:AssumeRole", "sts:TagSession"]
    principals {
      type        = "AWS"
      identifiers = concat([aws_iam_user.atlantis.arn], var.deployer_trusted_principals)
    }
  }
}

resource "aws_iam_role" "deployer" {
  name                 = "terraform-deployer"
  assume_role_policy   = data.aws_iam_policy_document.deployer_trust.json
  max_session_duration = 3600
}

# Lab: admin. Produção: política mínima por stack + permissions boundary.
resource "aws_iam_role_policy_attachment" "deployer_admin" {
  role       = aws_iam_role.deployer.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

# ---------------------------------------------------------------- custo
resource "aws_budgets_budget" "monthly" {
  name         = "lab-monthly"
  budget_type  = "COST"
  limit_amount = tostring(var.budget_limit_usd)
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  dynamic "notification" {
    for_each = { "50" = "ACTUAL", "80" = "ACTUAL", "100" = "FORECASTED" }
    content {
      comparison_operator        = "GREATER_THAN"
      threshold                  = tonumber(notification.key)
      threshold_type             = "PERCENTAGE"
      notification_type          = notification.value
      subscriber_email_addresses = [var.budget_email]
    }
  }
}
