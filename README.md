# infra-live

Os **ambientes**: cada diretório é um root module com state próprio que consome
[`terraform-modules`](https://github.com/patrickcmartins/terraform-modules) por tag. Mudança aqui só entra via PR,
e quem roda `plan`/`apply` é o [Atlantis](https://github.com/patrickcmartins/atlantis-server).

```
local/mgmt      kind "mgmt"      hub: Argo CD + root app ─► platform-gitops/bootstrap/hub
local/kind-dev  kind "kind-dev"  spoke dev  (registrado no hub)      state: Postgres
aws/prod/eks    EKS "eks-prod"   spoke prod (registrado no hub)      state: S3 + lockfile
aws/bootstrap   bucket, OIDC GitHub, role deployer, budget           aplicado por HUMANO
```

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
