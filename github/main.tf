# ---------------------------------------------------------------- environments
# Um GitHub Environment é a fronteira de "quem e o quê pode fazer deploy onde":
# secrets/variables só daquele ambiente, branches permitidas, aprovadores e histórico.

# sample-app: o CI faz deploy contínuo em stg (commit no sample-app-deploy).
resource "github_repository_environment" "app_staging" {
  repository  = "sample-app"
  environment = "staging"

  deployment_branch_policy {
    protected_branches     = false
    custom_branch_policies = true
  }
}

resource "github_repository_environment_deployment_policy" "app_staging_main" {
  repository     = "sample-app"
  environment    = github_repository_environment.app_staging.environment
  branch_pattern = "main"
}

resource "github_actions_environment_variable" "auto_deploy_stg" {
  repository    = "sample-app"
  environment   = github_repository_environment.app_staging.environment
  variable_name = "AUTO_DEPLOY_STG"
  value         = tostring(var.auto_deploy_stg)
}

# sample-app-deploy: promoção para prod exige aprovação humana.
resource "github_repository_environment" "deploy_production" {
  repository          = "sample-app-deploy"
  environment         = "production"
  prevent_self_review = var.prevent_self_review
  wait_timer          = 0

  reviewers {
    users = var.reviewers
  }

  deployment_branch_policy {
    protected_branches     = false
    custom_branch_policies = true
  }
}

resource "github_repository_environment_deployment_policy" "deploy_production_main" {
  repository     = "sample-app-deploy"
  environment    = github_repository_environment.deploy_production.environment
  branch_pattern = "main"
}

# ---------------------------------------------------------------- proteção da main
# Ruleset (o substituto moderno do branch protection): sem push direto, sem force push,
# sem apagar a main, e só com os checks verdes.
#
# Bypass: o admin do repo (RepositoryRole 5) pode passar por cima. Necessário aqui porque
# é UMA pessoa e o bot de CD (token do admin) faz commit direto no sample-app-deploy.
# Mundo ideal: o bot é um GitHub App listado como bypass e humanos NÃO têm bypass.
resource "github_repository_ruleset" "main" {
  for_each = var.required_checks

  name        = "main"
  repository  = each.key
  target      = "branch"
  enforcement = "active"

  conditions {
    ref_name {
      include = ["~DEFAULT_BRANCH"]
      exclude = []
    }
  }

  bypass_actors {
    actor_id    = 5 # RepositoryRole: Admin
    actor_type  = "RepositoryRole"
    bypass_mode = "always"
  }

  rules {
    deletion         = true
    non_fast_forward = true

    pull_request {
      # 0 porque o autor não pode aprovar o próprio PR e só existe uma pessoa.
      # Em time: 1 ou 2, com dismiss_stale_reviews e CODEOWNERS obrigatório.
      required_approving_review_count   = 0
      dismiss_stale_reviews_on_push     = true
      require_code_owner_review         = false
      require_last_push_approval        = false
      required_review_thread_resolution = true
    }

    required_status_checks {
      strict_required_status_checks_policy = false
      dynamic "required_check" {
        for_each = each.value
        content {
          context = required_check.value
        }
      }
    }
  }
}
