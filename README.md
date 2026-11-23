# infra-live

Os **ambientes**: cada diretório é um root module com state próprio que consome
[`terraform-modules`](https://github.com/patrickcmartins/terraform-modules) por tag. Mudança aqui só entra via PR,
e quem roda `plan`/`apply` é o [Atlantis](https://github.com/patrickcmartins/atlantis-server).

```
local/mgmt      kind "mgmt"      hub: Argo CD + root app ─► platform-gitops/bootstrap/hub
local/kind-dev  kind "kind-dev"  spoke dev  (registrado no hub)      state: Postgres
aws/stg/eks     EKS "eks-stg"    spoke stg  (registrado no hub)      state: S3 + lockfile
aws/prod/eks    EKS "eks-prod"   spoke prod (registrado no hub)      state: S3 + lockfile
aws/bootstrap   bucket, OIDC GitHub, role deployer, budget           aplicado por HUMANO
```

## Desenvolvimento local

```bash
pre-commit install          # uma vez por clone: fmt, validate, tflint e gitleaks no seu commit
pre-commit run --all-files  # rodar em tudo
```

Os mesmos checks rodam no CI (o hook local pode ser pulado; o CI não). Por que e como: [shift left](docs/shift-left.md).

## Decisões de arquitetura (ADRs)

- [0001: Topologia de ambientes](docs/adr/0001-topologia-de-ambientes.md): cluster por ambiente vs namespace por ambiente, com ganhos e perdas de cada um.
- [0002: Entrega de Terraform e locks](docs/adr/0002-terraform-entrega-e-locks.md): lock de state vs lock de PR, locks em time grande, e local, CI, Atlantis, TACOS ou Crossplane por tamanho de time e projeto.
- [0003: Autenticação do Terraform e do Argo CD no EKS](docs/adr/0003-autenticacao-terraform-eks.md): o token de 15 min, token estático vs exec, Access Entries, credenciais de curta duração, e a dívida do token do Argo CD.

## stg e prod: mesmo código, valores diferentes

`aws/stg/eks` e `aws/prod/eks` têm **o mesmo** `main.tf`, `variables.tf` e `outputs.tf`. O que muda entre eles mora
**só** no `terraform.tfvars` (nome, CIDR da VPC, labels) e na chave do state. O job `env-parity` do CI falha se o
código divergir, porque um stg diferente de prod não prova nada sobre prod. No `atlantis.yaml`, prod depende de stg:
num PR que mexe nos dois, stg é aplicado primeiro. Por que dois clusters e não dois namespaces: [ADR 0001](docs/adr/0001-topologia-de-ambientes.md).

## Ordem (e por quê)

1. **`aws/bootstrap`**: manual, fora do Atlantis, porque cria a identidade que o Atlantis usa. Ver o [README](aws/bootstrap/README.md).
2. **`local-mgmt`**: o hub tem que existir antes de qualquer spoke se registrar nele.
3. **`local-kind-dev`** e **`aws-prod-eks`**: `depends_on: [local-mgmt]` e `execution_order_group: 2` no `atlantis.yaml`.

Depois do passo 2, o Terraform não toca em mais nada dentro dos clusters: o Argo CD, olhando os
**labels** de cada Secret de cluster, instala o Istio e as apps.

## Fluxo de um PR

```
branch ─► PR ─► GitHub Actions (fmt, validate, tflint, trivy)  ─┐
              └► Atlantis autoplan ─► conftest (tags, destroy) ─┤
                                                                ▼
                       CI verde (= mergeable) ─► comentário "atlantis apply" ─► merge
```

| Comando no PR | Efeito |
|---|---|
| `atlantis plan -p local-kind-dev` | replan de um projeto |
| `atlantis apply -p local-mgmt` | aplica um projeto |
| `atlantis approve_policies` | policy owner libera uma violação (ex.: destruir cluster) |
| `atlantis unlock` | solta o lock do PR |

## Rodando local (debug)

```bash
export PG_CONN_STR="postgres://terraform:<senha>@127.0.0.1:15432/tfstate?sslmode=disable"
cd local/mgmt && terraform init && terraform plan
kind get kubeconfig --name mgmt > ~/.kube/mgmt
```

## Decisões que valem explicar

* **Um state por stack.** Assim o *blast radius* fica pequeno e o lock não trava o time inteiro.
* **Módulos por tag.** Prod só sobe de versão depois que dev validou.
* **`.trivyignore` com justificativa e `exp:`.** Exceção de segurança tem dono e prazo.
* **Secrets de cluster no state.** Os certs do hub vão para o state, e por isso o backend tem acesso restrito.
  Em produção, o Argo CD usaria IRSA/Pod Identity em vez de token.
