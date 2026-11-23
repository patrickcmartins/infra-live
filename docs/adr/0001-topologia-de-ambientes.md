# ADR 0001: Topologia de ambientes (cluster por ambiente vs namespace por ambiente)

- **Status:** aceita
- **Data:** 2026-11-23
- **Decisão:** um cluster EKS por ambiente (`eks-stg` e `eks-prod`), mesmo módulo Terraform, mesma pilha de addons via Argo CD. Dentro de cada cluster, um namespace por aplicação/time.

## Contexto

Precisamos de pelo menos dois ambientes (staging e produção) para o mesmo conjunto de serviços. A pergunta é **onde fica a fronteira entre eles**. Existem três modelos comuns, e a escolha muda custo, segurança, raio de impacto e o quanto o staging realmente prova que produção vai funcionar.

## As opções

### 1. Namespace por ambiente (um cluster, `app-stg` e `app-prod`)

```
eks-shared
├── sample-stg    (Deployment, Service, ...)
└── sample-prod   (Deployment, Service, ...)
```

| Ganha | Perde |
|---|---|
| **Custo**: um control plane (US$ 73/mês no EKS) e nodes compartilhados, com bin packing melhor. | **Raio de impacto**: um problema de cluster (upgrade de versão, CNI quebrado, CoreDNS caído, webhook com defeito, etcd lento) derruba stg **e** prod juntos. |
| **Operação**: um só Istio, um só Prometheus, um só conjunto de addons para manter. | **Addons não são testáveis**: o Istio, o cert-manager e o próprio Kubernetes são compartilhados. Não dá para testar o upgrade do Istio no stg antes do prod, porque ele é **o mesmo**. |
| **Velocidade**: criar um ambiente é criar um namespace (segundos). | **Isolamento fraco**: o namespace é uma fronteira lógica, não física. Recursos com escopo de cluster (CRDs, webhooks, ClusterRoles, StorageClasses, versão do Kubernetes) são um só. Um erro de RBAC ou uma NetworkPolicy faltando expõe prod a partir do stg. |
| Bom para ambientes **efêmeros** (um por PR, ApplicationSet com generator de PR). | **Vizinho barulhento**: um teste de carga no stg disputa CPU, memória, IPs da VPC e o limite da API com prod. ResourceQuota e LimitRange ajudam, mas não resolvem tudo (a rede e o API server são compartilhados). |
| | **Compliance**: auditores (SOC 2, PCI, SOX) costumam exigir que produção seja segregada. "Mesmo cluster, outro namespace" é difícil de defender. |

**Quando usar:** dev e preview environments, times pequenos, orçamento curto, workloads sem dado sensível, ou vários **times/apps** no mesmo ambiente (multi-tenancy por namespace **dentro** de um ambiente é o uso certo).

### 2. Cluster por ambiente (`eks-stg` e `eks-prod`), a escolhida

```
eks-stg   (conta/VPC de stg)    eks-prod  (conta/VPC de prod)
└── sample                      └── sample
```

| Ganha | Perde |
|---|---|
| **Raio de impacto contido**: o que quebra no stg fica no stg. | **Custo**: um control plane por ambiente, mais nodes que ficam ociosos no stg. |
| **Ensaio real de mudanças de plataforma**: upgrade de Kubernetes, do Istio ou de um addon roda **primeiro no stg**, com o mesmo código. É o que permite dizer que "stg provou que prod funciona". | **Mais coisas para operar**: N clusters para atualizar e observar. Só escala com automação: mesmo módulo Terraform, addons por **label** via ApplicationSet, e nada de configuração manual. |
| **Isolamento forte**: rede, IAM (Pod Identity por cluster), quotas da API, versão do Kubernetes e CRDs, tudo separado. Fácil de explicar para auditoria. | **Drift entre ambientes**: se stg e prod divergem (versões, values), o stg para de provar coisas. Mitigação: mesmo módulo, diferenças **só** em arquivo de values, e promoção por PR. |
| **Permissões diferentes**: o time pode ter acesso amplo no stg e acesso só por pipeline em prod. | Mais tempo para criar um ambiente novo (cerca de 15 min de EKS, em vez de segundos). |

**Quando usar:** sempre que existir **produção de verdade**. É o padrão de mercado para stg × prod. Na AWS, o passo seguinte é **uma conta por ambiente** (AWS Organizations), para separar também billing, IAM e limites de serviço.

### 3. Cluster por time/app (ou por região) dentro de cada ambiente

| Ganha | Perde |
|---|---|
| Isolamento máximo, e cada time tem seu ciclo de upgrade. | Explosão de clusters e de custo; os addons se repetem N vezes. |
| Exigido por requisitos fortes (PCI isolado, dados regulados, latência por região, DR ativo-ativo). | Exige plataforma madura (frota gerenciada como gado, não como pet). |

**Quando usar:** escala grande, requisitos regulatórios, multi-região ou DR. Não faz sentido no tamanho deste lab.

## Resumo para decidir rápido

| Pergunta | Se a resposta for "sim" |
|---|---|
| Tem produção com cliente real ou dado sensível? | Cluster (e de preferência conta) separado para prod. |
| Precisa ensaiar upgrade de Kubernetes, do mesh ou de addons antes de prod? | Cluster por ambiente. |
| É ambiente efêmero (um por PR) ou de dev individual? | Namespace. |
| Vários times no **mesmo** ambiente? | Namespace por time, com quotas, NetworkPolicy, AuthorizationPolicy e AppProject por time. |
| Orçamento muito curto e nada crítico? | Namespace, aceitando o risco **por escrito** (como nesta ADR). |

## Decisão neste lab

- `eks-stg` e `eks-prod`: **mesmo módulo** (`terraform-modules//modules/aws-eks`), stacks separadas em `aws/stg/eks` e `aws/prod/eks`, com state separado e VPCs separadas.
- O que muda entre eles fica **só** em variáveis: labels, tamanho dos nodes e quais addons ligam (por label: `observability`, `messaging`).
- O **hub** (Argo CD, no `mgmt`) gerencia os dois. Uma mudança de app entra no stg por merge e vai para prod por **PR de promoção**. Uma mudança de plataforma (versão do Istio, de um chart) entra primeiro no values do stg.
- Dentro de cada cluster: **namespace por app** (`sample`), com AppProject restrito, AuthorizationPolicy (zero trust) e quotas.
- No lab, tudo fica na mesma conta AWS, por custo. **Em produção de verdade:** uma conta por ambiente.

## Consequências e custos

- Os dois clusters juntos custam cerca de US$ 0,50/h (2 control planes, mais 4 nodes spot `t3.xlarge` e os NLBs). Ficam ligados só durante o estudo e são destruídos por PR (`atlantis plan -- -destroy`, com `approve_policies`).
- O `kind-dev` local deixa de ser necessário para o fluxo stg → prod e pode ser destruído para liberar RAM no PC.

## Quando revisitar

- Se o custo de dois clusters virar problema e o stg não estiver sendo usado para ensaiar mudanças de plataforma.
- Se surgirem muitos ambientes efêmeros: adicionar previews **por namespace** dentro do `eks-stg`, que é um modelo híbrido e o mais comum na prática.
