# github

GitHub como código: **GitHub Environments** e **proteção da `main`** (rulesets) dos 7 repositórios.

| Recurso | Para quê |
|---|---|
| `sample-app` → environment `staging` | O job de CD (`bump-stg`) só roda da `main`; o `DEPLOY_REPO_TOKEN` é secret **do environment**, invisível para outros jobs. |
| `sample-app-deploy` → environment `production` | O workflow de promoção para prod **pausa** até um aprovador liberar. Fica registrado quem aprovou e quando. |
| Ruleset `main` em todos os repos | Sem force push, sem apagar a `main`, merge só com os checks verdes. No `infra-live`, `atlantis/apply` é obrigatório: o PR só entra depois de aplicado. |

Por que como código: uma mudança em "quem aprova prod" passa por PR, review e histórico, igual a qualquer infra.
A alternativa (configurar na UI) não deixa trilha, não é revisável e diverge entre repos.

**Limites assumidos no lab** (uma pessoa só): `prevent_self_review = false`, 0 aprovações obrigatórias em PR e bypass para o admin.
Em time: `prevent_self_review = true`, 1–2 aprovações, CODEOWNERS obrigatório e bypass só para um GitHub App de automação.

## Token

O provider lê `GITHUB_TOKEN` do ambiente do Atlantis (`GITHUB_ADMIN_TOKEN` no `.env` do `atlantis-server`).
PAT fine-grained, só nos 7 repos, com: **Administration: RW**, **Environments: RW**, **Variables: RW**, **Metadata: R**.
Mundo ideal: GitHub App com essas permissões (token de 1 h, sem pessoa por trás).

Secrets (ex.: `DEPLOY_REPO_TOKEN`) **não** ficam aqui: iriam em texto puro para o state. Crie na UI ou com
`gh secret set DEPLOY_REPO_TOKEN -R patrickcmartins/sample-app --env staging`.
