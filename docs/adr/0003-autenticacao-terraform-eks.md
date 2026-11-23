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

### Como é hoje

Para o hub (Argo CD, num kind local) falar com os clusters EKS, cada stack de spoke cria:

1. uma ServiceAccount `argocd-manager` no spoke, com **cluster-admin**;
2. um Secret `kubernetes.io/service-account-token`, ou seja, um **token que nunca expira**;
3. o Secret de cluster no hub com esse token (`bearerToken`).

| Problema | Por que importa |
|---|---|
| O token não expira | Se vazar (backup do etcd do hub, alguém com `get secret` no namespace `argocd`, log mal configurado), dá cluster-admin em prod **até alguém perceber e revogar** |
| É um segredo guardado | Precisa de rotação, de proteção e de auditoria: trabalho que ninguém faz até o dia do incidente |
| cluster-admin | O Argo CD precisa de muito (CRDs e webhooks do Istio e do Strimzi), mas não de tudo |

### O jeito certo na AWS: hub no EKS, autenticando por IAM

A ideia central: **trocar "um segredo guardado" por "uma identidade"**. O Argo CD deixa de ter um token e passa a *ser* uma role IAM. Cada vez que precisa falar com um spoke, ele gera um token do EKS de 15 min a partir dessa identidade, exatamente como o `aws eks get-token` da Parte 2.

São três peças.

#### Peça 1: EKS Pod Identity (o pod do Argo CD ganha uma role IAM)

```
hub (EKS)
├── addon eks-pod-identity-agent    DaemonSet em cada node (já ligado no nosso módulo aws-eks)
└── namespace argocd
    ├── SA argocd-application-controller ─┐
    └── SA argocd-server ─────────────────┴─ Pod Identity Association ─► role IAM "argocd-hub"
```

- Uma **Pod Identity Association** (`aws_eks_pod_identity_association`) diz: "a ServiceAccount X, no namespace Y deste cluster, assume a role Z".
- O agente intercepta o pedido de credencial do pod e entrega **credenciais temporárias** dessa role (o SDK da AWS no pod as encontra sozinho, via `AWS_CONTAINER_CREDENTIALS_FULL_URI`).
- A trust policy da role é **genérica**: `Principal: pods.eks.amazonaws.com`, ações `sts:AssumeRole` e `sts:TagSession`. Quem amarra role a pod é a association, não a trust policy.
- **Nenhuma chave** em lugar nenhum: as credenciais duram horas e são renovadas sozinhas.

> **IRSA** (IAM Roles for Service Accounts) é a forma anterior: um provedor OIDC por cluster e uma trust policy com o `sub` `system:serviceaccount:argocd:argocd-application-controller`. Funciona igual na prática. O Pod Identity é mais simples (sem provedor OIDC por cluster, trust policy reutilizável, associação por API) e é a recomendação atual para EKS. O IRSA ainda aparece muito em sistemas existentes e em casos fora do EKS.

#### Peça 2: `awsAuthConfig` no Secret de cluster do Argo CD (sem token nenhum)

Hoje (token guardado):

```yaml
# Secret do cluster eks-prod no hub
stringData:
  name: eks-prod
  server: https://XXXX.gr7.us-east-2.eks.amazonaws.com
  config: |
    { "bearerToken": "eyJhbGciOi...(nunca expira)...",
      "tlsClientConfig": { "caData": "LS0t..." } }
```

Mundo ideal (identidade):

```yaml
stringData:
  name: eks-prod
  server: https://XXXX.gr7.us-east-2.eks.amazonaws.com
  config: |
    { "awsAuthConfig": {
        "clusterName": "eks-prod",
        "roleARN": "arn:aws:iam::<CONTA-PROD>:role/argocd-deployer-prod" },
      "tlsClientConfig": { "caData": "LS0t..." } }
```

O que acontece a cada sincronização:

```
1. o application-controller precisa falar com o eks-prod
2. chama "argocd-k8s-auth aws" (binário que vem na imagem do Argo CD)
3. com a credencial do Pod Identity (role argocd-hub) faz sts:AssumeRole na roleARN do spoke
4. com essa credencial, assina um sts:GetCallerIdentity = token do EKS (15 min), e reusa até expirar
5. o eks-prod valida no STS, vê "role/argocd-deployer-prod" e aplica a Access Entry dela
```

**O que fica guardado no hub: só o endereço, a CA e o nome de uma role. Nada que dê acesso sozinho.** Vazou o Secret? O atacante não consegue usar sem também **ser** a role `argocd-hub`, o que só acontece dentro do pod do Argo CD, naquele cluster.

#### Peça 3: em cada spoke, uma Access Entry para a role do Argo CD

```hcl
# no stack do spoke (aws/prod/eks), em vez da ServiceAccount + token:
access_entries = {
  argocd = {
    principal_arn = "arn:aws:iam::<CONTA-PROD>:role/argocd-deployer-prod"
    # Lab: admin. Ideal: kubernetes_groups = ["argocd-deployer"] + um ClusterRole
    # com só o que o Argo CD aplica (CRDs, webhooks, namespaces dos addons e das apps).
    policy_associations = {
      admin = {
        policy_arn   = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
        access_scope = { type = "cluster" }
      }
    }
  }
}
```

E a role do spoke confia na role do hub (role chaining):

```hcl
# trust policy de argocd-deployer-prod
principals { type = "AWS", identifiers = ["arn:aws:iam::<CONTA-HUB>:role/argocd-hub"] }
actions    = ["sts:AssumeRole", "sts:TagSession"]
```

### Por que uma role por spoke (e não a role do hub direto em todos)

| Desenho | Ganha | Perde |
|---|---|---|
| **A role do hub tem Access Entry em todos os clusters** | Simples: uma role, sem `roleARN` | Comprometeu o hub = acesso a tudo. Não dá para revogar um ambiente sem afetar os outros. Não funciona bem entre contas. |
| **Uma role por spoke** (`roleARN` no `awsAuthConfig`), assumida pela role do hub | Revoga prod sem tocar stg; permissões diferentes por ambiente; **funciona entre contas** (o hub numa conta de "tooling", os spokes nas contas de stg e prod); o CloudTrail mostra qual role tocou qual cluster | Uma role e uma trust policy por spoke (é só Terraform; o módulo do spoke cria) |

Em empresa com **uma conta por ambiente** (ADR 0001), a segunda opção é a única que escala.

### Comparando as alternativas

| Opção | Segredo guardado? | Expira? | Funciona com o hub fora da AWS? | Comentário |
|---|---|---|---|---|
| Token de SA sem expiração (**hoje**) | Sim | Nunca | Sim | Simples e perigoso. Aceitável só em lab, e documentado como dívida. |
| Token de SA **com expiração** (TokenRequest) + rotação automática | Sim | Sim (horas/dias) | Sim | Melhor que hoje, mas exige um job ou operador de rotação (e se a rotação parar, o deploy para). |
| **`awsAuthConfig` + Pod Identity/IRSA** (hub no EKS) | **Não** | Token de 15 min, renovado sozinho | Não | **O padrão para Argo CD gerenciando EKS.** |
| **Argo CD Agent** (modelo *pull*) | O agente no spoke tem a credencial dele | Depende | Sim | Inverte a direção: o spoke busca o que aplicar. O hub não precisa de acesso de entrada aos clusters (bom para redes isoladas e escala grande). Mais peças para operar. |

### Tradeoffs de colocar o hub no EKS

| Ganha | Perde |
|---|---|
| Zero segredo de acesso aos clusters, rotação automática, auditoria no CloudTrail | **Custo:** mais um cluster (ou o hub dentro de um cluster de "tooling" compartilhado) |
| O Argo CD fica perto dos spokes (latência, rede privada via peering/Transit Gateway em vez de endpoints públicos) | **O hub vira peça crítica:** fora do ar, nada é implantado (o que já está rodando continua). Pede HA (réplicas do controller e do repo-server, Redis HA) e DR (o hub inteiro recriável por Terraform + bootstrap do Argo CD em minutos). |
| Encaixa no modelo de contas separadas (hub em conta de tooling) | **Quem cria o hub?** Ele não pode se gerenciar do zero: o bootstrap do hub é Terraform (ou um script), fora do próprio Argo CD (o "problema do ovo e da galinha"). |
| | Raio de impacto: um hub para tudo é um alvo valioso. Empresas grandes usam **um hub para não-prod e outro para prod**. |

### Por que não fizemos isso neste lab

O hub é um **kind no PC**, e o Pod Identity e o IRSA só existem dentro do EKS. Para ter a solução completa seria preciso um terceiro EKS (o hub), mais uns US$ 0,10/h de control plane mais os nodes, ou mover o Argo CD para um dos spokes, o que mistura "gerenciador" com "gerenciado". A dívida fica registrada com o desenho acima pronto para implementar.

---

## Resumo para a entrevista

> "EKS auth is IAM-based: the client presigns an STS GetCallerIdentity call and sends it as a bearer token, valid for 15 minutes, and EKS maps the IAM principal to Kubernetes permissions through Access Entries. Our Terraform used a static token from a data source; a cluster creation that took longer than 15 minutes made the in-cluster resources fail with Unauthorized. We switched to exec-based auth, so each call gets a fresh token. In a real setup I'd also split cluster creation from in-cluster bootstrap, keep everything short-lived (SSO for humans, OIDC for CI, Pod Identity for workloads), and replace the Argo CD long-lived ServiceAccount token with IAM-based auth from a hub running on EKS."
