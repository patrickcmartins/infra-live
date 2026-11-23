# ADR 0003: Como o Terraform (e o Argo CD) se autenticam no EKS

- **Status:** aceita
- **Data:** 2026-11-23
- **Decisão:** provider `kubernetes` com autenticação **`exec`** (`aws eks get-token`), Access Entries no lugar do `aws-auth`, e credenciais sempre de curta duração. Dívidas registradas no fim.

---

## O incidente que motivou esta ADR

Ao criar o `eks-stg`, o apply levou cerca de 20 minutos. A AWS criou tudo (VPC, control plane, nodes, addons), mas os últimos 4 recursos, **dentro** do cluster (a ServiceAccount do Argo CD, o RBAC, o token e o registro no hub), falharam com:

```
Error: Unauthorized
  with kubernetes_service_account_v1.argocd_manager
```

A primeira criação do `eks-prod` tinha falhado igual. Ela "se resolveu" quando o apply foi repetido, e ninguém investigou. **Erro que some quando se repete é sintoma, não sorte.**

---

## Parte 1: como funciona a autenticação no EKS

O EKS não tem usuário nem senha. Ele usa a identidade da **AWS (IAM)**:

```
1. o cliente tem credencial AWS (usuário, role, SSO, OIDC)
2. gera um TOKEN: uma URL pré-assinada de sts:GetCallerIdentity, em base64 ("k8s-aws-v1.xxxx")
3. manda o token como Bearer para a API do Kubernetes
4. o EKS chama o STS com a URL, descobre "quem é" (o ARN) e
5. mapeia o ARN para permissões: Access Entries (API do EKS) ou o aws-auth (ConfigMap, legado)
```

Pontos que caem em entrevista:

- **O token vale 15 minutos**, mesmo que a credencial AWS por trás dure horas. É assim de propósito: um token vazado tem vida curta.
- **O token não fica guardado em lugar nenhum do EKS**: cada chamada é validada no STS.
- **Access Entries** (`authentication_mode = "API"`, que usamos aqui) substituem o ConfigMap `aws-auth`. São recursos da API da AWS, gerenciados por Terraform, auditados no CloudTrail, e não dá para "trancar todo mundo para fora" editando um YAML errado (o que acontecia com o `aws-auth`).

---

## Parte 2: as formas de o provider `kubernetes` se autenticar

| Forma | Como | Ganha | Perde |
|---|---|---|---|
| **Token estático** (`data "aws_eks_cluster_auth"`) | O Terraform gera o token **uma vez**, no início do run | Não depende de binário externo (nada de aws-cli); simples | **Expira em 15 min.** Run longo (criar cluster) = `Unauthorized` no meio. O token também vai parar dentro do **arquivo de plan** salvo (o Atlantis guarda planos em disco). |
| **Exec plugin** (`exec { command = "aws", args = ["eks","get-token",...] }`) | O provider chama o aws-cli **a cada vez** que precisa de um token | Token sempre novo, então runs de qualquer duração funcionam. Usa a mesma cadeia de credenciais do resto (profile, assume-role, OIDC). **É o recomendado pela HashiCorp e pela AWS.** | Precisa do `aws` instalado onde o Terraform roda (runner, Atlantis, CI) |
| **Kubeconfig em arquivo** (`config_path = "~/.kube/config"`) | Lê o kubeconfig da máquina | Cômodo no laptop | Depende do estado da máquina de quem roda; em CI/Atlantis é **anti-padrão** (o contexto errado aplica no cluster errado) |
| **Token de ServiceAccount de longa duração** | Secret `kubernetes.io/service-account-token` | Funciona de qualquer lugar, sem AWS | **Não expira nunca.** Se vazar, vale até alguém revogar. Ver Parte 4. |

### Por que eu fiz com token estático antes (o erro de raciocínio)

A escolha foi **evitar uma dependência**: sem o aws-cli, a imagem do Atlantis fica menor e mais simples. Mas o custo real (applies longos quebrando) é muito maior que o ganho (uns MB na imagem). O tradeoff foi avaliado pelo lado errado. A correção:

1. `aws-cli` na imagem do Atlantis (`atlantis-server/Dockerfile`).
2. `exec` no provider das duas stacks (stg e prod idênticas: o check `env-parity` garante).
3. Um efeito colateral: o aws-cli **grava cache** de credenciais em `~/.aws/cli/cache`, e esse diretório era um volume **read-only** com os segredos. Os segredos foram para `/etc/aws-secrets` (read-only), com `AWS_CONFIG_FILE` e `AWS_SHARED_CREDENTIALS_FILE` apontando para lá, e o `~/.aws` voltou a ser gravável. Segredo read-only e cache gravável, cada um no seu lugar.

---

## Parte 3: como se faz no mundo real

### 1. Separar "criar o cluster" de "configurar dentro do cluster"

A HashiCorp desaconselha configurar o provider `kubernetes` (ou `helm`) com valores de um cluster **criado no mesmo apply**. Além do token, há o problema do "known after apply": no primeiro plan o endpoint do cluster ainda não existe, e o provider é configurado com valores desconhecidos.

```
stack A: aws/prod/eks             -> VPC, EKS, node groups, addons, Access Entries
stack B: aws/prod/eks-bootstrap   -> o que vai DENTRO do cluster, via remote state de A
                                     (ou nada disso: o Argo CD instala tudo, GitOps)
```

| Ganha | Perde |
|---|---|
| Cada apply é curto e focado; um erro dentro do cluster não deixa o cluster pela metade | Mais uma stack e uma ordem de execução (`depends_on` no `atlantis.yaml`) |
| Dá para recriar o bootstrap sem tocar no cluster | |

**Neste lab:** o que roda dentro do cluster via Terraform é **mínimo** (só a identidade do Argo CD e o registro no hub). Todo o resto é do Argo CD. Com auth `exec`, manter os dois na mesma stack é aceitável, mas a separação é o próximo passo natural.

### 2. Nada de credencial de longa duração

| Quem | Lab hoje | Mundo ideal |
|---|---|---|
| **Humanos** | SSO (IAM Identity Center), role `AccountFullAccessRole` via Access Entry | Igual: SSO com MFA, sessão de horas, **nenhuma** access key pessoal |
| **CI (GitHub Actions)** | **OIDC** (`aws-github-oidc`): role por `sub` do repo/branch/environment, sem chave | Igual, com `environment` no `sub` para separar stg e prod |
| **Atlantis** | **Usuário IAM `atlantis-local` com access key** que só pode assumir o `terraform-deployer` (credencial de 1 h) | Atlantis **rodando na AWS** (ECS/EKS) com **role própria** (task role ou Pod Identity): **zero chaves**. A chave existe aqui porque o Atlantis roda no PC. É dívida assumida, e mitigada: a chave sozinha não faz nada além de `sts:AssumeRole`. |
| **Pods no EKS** (external-dns, cert-manager) | (próximo passo) | **EKS Pod Identity** (ou IRSA): cada ServiceAccount assume uma role, com credencial temporária injetada |
| **Argo CD → clusters** | Token de ServiceAccount **sem expiração** (Parte 4) | Ver abaixo |

### 3. Privilégio mínimo também no Kubernetes

As Access Entries aceitam *access policies* com escopo: `AmazonEKSClusterAdminPolicy` (tudo), `AmazonEKSAdminPolicy`, `AmazonEKSEditPolicy` e `AmazonEKSViewPolicy`, por cluster ou **por namespace**. Um time de app recebe `Edit` só nos namespaces dele, e não admin de cluster.

---

## Parte 4: a dívida que esta análise revelou (Argo CD → clusters)

Para o hub (Argo CD, no kind local) falar com os clusters EKS, criamos uma ServiceAccount `argocd-manager` com **cluster-admin** e um **token sem expiração** (Secret do tipo `service-account-token`), guardado no Secret de cluster do Argo CD.

| Problema | Por que importa |
|---|---|
| O token não expira | Se vazar (backup do etcd do hub, `kubectl get secret` de alguém com acesso), dá cluster-admin em prod até alguém revogar |
| cluster-admin | O Argo CD precisa de CRDs e webhooks (Istio, Strimzi), mas poderia ter um ClusterRole mais restrito |

**Como resolvem no mundo real:**

1. **Hub rodando no EKS** com **IRSA ou Pod Identity**: o Secret de cluster do Argo CD usa `awsAuthConfig` (`clusterName` + `roleARN`), o Argo CD gera tokens do EKS de 15 min sob demanda, e **não existe token guardado**. Cada spoke dá à role do hub uma Access Entry.
2. Se o hub não estiver na AWS: um token de ServiceAccount **com expiração** (TokenRequest API) mais rotação automática (External Secrets ou um job), ou o **agent do Argo CD** (modelo *pull*, em que o spoke busca a configuração e o hub não precisa de credencial para entrar nele).

**Neste lab** o hub é um kind no PC, então não há como usar IRSA ou Pod Identity. A dívida fica registrada, com a solução definida para quando o hub for para a AWS.

---

## Resumo para a entrevista

> "EKS auth is IAM-based: the client presigns an STS GetCallerIdentity call and sends it as a bearer token, valid for 15 minutes, and EKS maps the IAM principal to Kubernetes permissions through Access Entries. Our Terraform used a static token from a data source; a cluster creation that took longer than 15 minutes made the in-cluster resources fail with Unauthorized. We switched to exec-based auth, so each call gets a fresh token. In a real setup I'd also split cluster creation from in-cluster bootstrap, keep everything short-lived (SSO for humans, OIDC for CI, Pod Identity for workloads), and replace the Argo CD long-lived ServiceAccount token with IAM-based auth from a hub running on EKS."
