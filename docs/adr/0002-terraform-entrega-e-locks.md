# ADR 0002: Como o Terraform é entregue (GitOps de infra) e como os locks funcionam

- **Status:** aceita
- **Data:** 2026-11-23
- **Decisão:** Atlantis, com *apply antes do merge*, lock por projeto e state pequeno por ambiente/componente. Ver "Decisão neste lab".

---

## Parte 1: os dois locks (e por que são coisas diferentes)

Em entrevista, a resposta boa começa separando os dois:

| | **Lock de state** (backend) | **Lock de PR** (Atlantis) |
|---|---|---|
| Quem cria | O próprio Terraform, no backend (S3 `use_lockfile`, DynamoDB no legado, advisory lock no Postgres, HCP Terraform) | O Atlantis, por **projeto** (`dir` + `workspace`) |
| Quanto dura | **Segundos ou minutos**: só enquanto um `plan` ou `apply` roda | **Horas ou dias**: do primeiro `plan` do PR até o merge, o fechamento ou um `atlantis unlock` |
| Protege contra | Duas execuções escrevendo o state ao mesmo tempo, o que **corrompe o state** | Dois PRs mudando a mesma infraestrutura em paralelo, um **desfazendo o outro** |
| Sem ele | State corrompido ou recursos duplicados | PR B aplica o código **sem** a mudança do PR A (que já foi aplicada mas ainda não está na `main`), e o apply de B **reverte** A em produção sem ninguém perceber |

### O que aconteceu neste lab (o exemplo real)

1. O PR #1 fez `plan` e `apply` do `aws-prod-eks`, e o Atlantis travou o projeto **para o PR #1**.
2. O PR #1 ficou aberto (aplicado, mas sem merge).
3. O PR #2 tentou planejar o `aws-prod-eks` e recebeu `This project is currently locked by an unapplied plan from pull #1`.
4. Por quê: o branch do PR #2 não necessariamente contém o que o #1 aplicou. Se o #2 aplicasse, poderia apagar a regra de security group que o #1 criou.
5. **Resolução correta:** fazer o merge do #1 (agora a `main` reflete a realidade, e o lock é liberado) e depois rodar o plan de novo no #2.

Uma segunda proteção apareceu no mesmo dia: um push depois do plan fez o `apply` ser recusado (`recorded plan status is from commit X but current head is Y`). **Um plan só vale para o commit que ele viu.**

---

## Parte 2: lock em time grande

### O problema

Num time com muita gente, o lock de PR vira **fila**. Se o `aws/prod` é um state gigante (VPC + EKS + RDS + IAM + DNS), qualquer PR em qualquer parte dele trava **todos** os outros. Os sintomas:

- PRs esperando horas porque alguém fez plan na sexta e saiu de férias.
- Gente usando `atlantis unlock` para furar a fila, o que traz de volta o risco de uma mudança reverter outra.
- Pressão para "juntar tudo num PR só", que deixa os PRs maiores, mais arriscados e com revisão pior.

### O que se faz no mundo real

| Prática | Como ajuda | Custo |
|---|---|---|
| **Quebrar o state por raio de impacto** (por ambiente × componente: `prod/network`, `prod/eks`, `prod/data`, `prod/iam`) | Os locks param de colidir: quem mexe no RDS não trava quem mexe no EKS. **É a medida mais importante.** | Dependências entre stacks (`terraform_remote_state` ou data sources) e uma ordem de apply (`depends_on` no `atlantis.yaml`) |
| **PRs pequenos e de vida curta**; apply e merge no mesmo dia | O lock fica segurado por pouco tempo | Disciplina e cultura |
| **CODEOWNERS por diretório** | Cada time revisa e aplica só o seu pedaço; nada de fila global | Mapear dono por diretório |
| **`repo_locks: on_apply`** (em vez de `on_plan`) | Planejar não trava: o lock só existe no momento do apply | Plans ficam desatualizados com mais frequência (o `undiverged` exige plan de novo) |
| **Merge queue** + requisito `undiverged` | PRs entram na `main` em ordem, sempre rebaseados | Mais tempo de CI |
| **Política de lock velho**: alerta ou expiração para lock parado há mais de X horas | Evita o "lock de férias" | Processo para destravar com segurança (avisar o dono) |
| **Pipeline por camada**: rede e IAM mudam pouco, apps mudam muito | Separa a cadência | Mais stacks para operar |

**Tradeoff central:** *locks mais longos = mais segurança e mais fila; locks mais curtos = mais vazão e mais risco de uma mudança atropelar outra.* A saída de verdade é **diminuir a área de cada lock** (states menores), não enfraquecer o lock.

---

## Parte 3: modelos de entrega de Terraform ("GitOps de infra")

### Primeiro: Terraform com PR é GitOps?

Os princípios do OpenGitOps são: (1) declarativo, (2) versionado e imutável no Git, (3) **puxado** automaticamente, (4) **reconciliado continuamente**.

- Atlantis e CI atendem 1 e 2, e a 3 só em parte (é *push*, disparado pelo PR). **Não atendem a 4**: se alguém muda algo no console, nada corrige sozinho. Por isso existe a **detecção de drift agendada** (o nosso `terraform-drift.yml`: `plan -detailed-exitcode` diário, que abre issue).
- Controladores no cluster (Tofu Controller, Crossplane) atendem os 4. Eles são o "GitOps puro" para infra, e têm outros custos (abaixo).

### Os modelos

| Modelo | Como funciona | Ganha | Perde |
|---|---|---|---|
| **1. Local** (`terraform apply` do laptop, com state remoto) | A pessoa roda | Zero infraestrutura, rápido | Sem revisão obrigatória, credencial forte no laptop, "funcionou na minha máquina", sem trilha de auditoria |
| **2. CI genérico** (GitHub Actions ou GitLab: plan no PR, **apply depois do merge**) | O plan é postado no PR; o merge na `main` dispara o apply (com GitHub Environment e aprovação para prod) | Usa o que já existe; OIDC sem chave; simples | **Apply falha depois do merge**: a `main` diz uma coisa e a nuvem tem outra, e a correção é fix-forward. Concorrência via `concurrency:` do workflow. O plan aprovado pode não ser o aplicado (a `main` andou). |
| **3. Atlantis** (self-hosted, **apply antes do merge**) | Comentários no PR (`atlantis plan/apply`), lock por projeto, policy check (conftest) | O PR só entra na `main` depois do apply funcionar, então **a `main` = o que está aplicado**. Lock de PR, trilha no próprio PR, gratuito, open source. | **Você opera** o servidor: alta disponibilidade, upgrade, segredos. Ele guarda credenciais poderosas e é alvo de ataque (precisa de rede e IAM restritos). As filas de lock em times grandes (Parte 2). UI e RBAC limitados. |
| **4. TACOS** (HCP Terraform/Terraform Cloud, Spacelift, env0, Scalr) | SaaS ou self-hosted gerenciado; *runs* disparados por VCS | RBAC e SSO, policy (Sentinel/OPA), **drift detection** e auditoria prontos, estimativa de custo, registry privado, *stacks* com dependências, *no-code provisioning* para times de app | **Custo** (o HCP cobra por recurso gerenciado), dependência de fornecedor, menos controle sobre o runner, e os dados de state ficam com terceiro (pesa em compliance) |
| **5. Controlador no Kubernetes** (Flux **Tofu Controller**, **Crossplane**) | Um operador no cluster reconcilia continuamente o desejado no Git com a nuvem | **Reconciliação contínua** (drift corrigido sozinho); um modelo só para app e infra (tudo via Argo CD/Flux); *self-service* por CRD (Crossplane Compositions) | Auto-apply contínuo é arriscado: **um erro no Git é aplicado sozinho**, sem um humano ler o plan. A visibilidade do plan é pior. O cluster que gerencia a infra vira dependência crítica (e quem cria esse cluster?). O Crossplane **não é Terraform**: outro modelo, outra curva. |

### Organização do código (vale para qualquer modelo)

| Opção | Ganha | Perde |
|---|---|---|
| **Módulos em repo separado, versionados por tag** (este lab: `terraform-modules@v0.2.0`) | Mudança em módulo é explícita: cada ambiente sobe a versão por PR (o stg primeiro). Testes do módulo isolados. | O bump de versão dá trabalho, e propagar um fix exige N PRs |
| Módulos no mesmo repo (`../modules`) | Mudança atômica, simples | Um PR em módulo afeta **todos** os ambientes de uma vez; o `ATLANTIS_AUTOPLAN_MODULES` replaneja tudo |
| **Monorepo `infra-live`** (este lab) | Visão única, refactors fáceis, um lugar só para policy e CI | Permissões grossas (o CODEOWNERS ajuda); CI e autoplan maiores |
| Repo por time ou ambiente | Isolamento de acesso, cadência própria | Duplicação e drift de padrões entre repos |
| **Terragrunt** (ou stacks do HCP) | DRY para dezenas de ambientes e regiões (backend e providers gerados) | Mais uma ferramenta e camada de indireção |
| Diretórios por ambiente (este lab) **vs** workspaces do Terraform | Diretórios: diferenças explícitas e visíveis em PR, state e permissões separados. Workspaces: mesmo código, menos arquivos | Diretórios: arquivos repetidos (mitigado pelo check `env-parity` do CI). Workspaces: é fácil aplicar no workspace errado, e o mesmo backend e as mesmas credenciais servem para todos, então **não use workspaces para separar prod de stg** |

---

## Parte 4: o que escolher, por contexto

| Contexto | Recomendação | Por quê |
|---|---|---|
| **Sozinho, projeto pequeno ou POC** | Local, mas com **state remoto e lock** (S3), e depois CI simples | O custo de montar Atlantis ou TACOS não se paga. O mínimo inegociável é o state remoto (nunca o `terraform.tfstate` no Git). |
| **Time pequeno (2–8), projeto pequeno ou médio** | **CI (GitHub Actions)**: plan no PR, apply no merge, GitHub Environment com aprovação para prod, OIDC | Usa o que já existe e não há servidor para operar. A falha pós-merge é rara e gerenciável num time pequeno. |
| **Time médio, vários ambientes, mudanças frequentes** | **Atlantis** (ou CI com apply antes do merge) | A `main` sempre igual ao aplicado; lock por projeto evita atropelos; policy check no PR. O custo de operar o servidor é baixo nesse tamanho. |
| **Vários times, muitas stacks, compliance (SOC 2, SOX)** | **TACOS** (HCP Terraform, Spacelift) **ou** Atlantis com operação madura | RBAC e SSO, auditoria, drift e policy prontos. A decisão é custo da licença versus custo de operar e construir isso por conta própria. |
| **Plataforma interna com self-service para times de app** | **Crossplane** (ou TACOS no-code) para recursos de app (bucket, fila, banco), e Terraform para a fundação (rede, contas, cluster) | O time de app pede um `PostgreSQL` por CRD no mesmo fluxo GitOps do app; a plataforma controla o que pode ser pedido. |
| **Muito grande (dezenas de contas, multi-região)** | TACOS ou Atlantis + **Terragrunt** + states pequenos + merge queue + drift diário | A escala exige DRY e locks pequenos; sem isso a fila de locks paralisa o time. |

### Atlantis vs HCP Terraform (resposta curta para treinar em voz alta)

> "Atlantis is free, self-hosted and PR-centric: apply happens before merge, so main always matches what's deployed, and it locks per project so two PRs can't step on each other. The cost is that I operate it, and it holds powerful credentials, so it needs tight network and IAM. HCP Terraform gives you RBAC, SSO, policy with Sentinel or OPA, drift detection and audit out of the box, and you pay per managed resource. For a small or medium team I'd pick Atlantis or plain CI. With many teams and audit requirements, a TACOS starts paying for itself. Either way the big lever is the same: small states split by blast radius, so locks don't become a queue."

---

## Decisão neste lab

- **Atlantis**, com apply antes do merge, `repo_locks: on_plan`, `apply_requirements: [mergeable, undiverged]` e policy check (conftest) obrigatório.
- **State pequeno por ambiente e componente**: `local/mgmt`, `local/kind-dev`, `aws/stg/eks`, `aws/prod/eks`, e `aws/bootstrap` (fora do Atlantis, aplicado por humano).
- **Drift diário** por GitHub Actions com OIDC somente leitura, para cobrir a falta de reconciliação contínua.
- Módulos versionados por tag (release-please), e stg e prod com código idêntico (check `env-parity` no CI).

## Quando revisitar

- Mais de um time aplicando no mesmo repo, ou filas de lock frequentes: quebrar mais os states, usar `on_apply` e merge queue.
- Exigência de SSO, RBAC fino e auditoria centralizada: avaliar HCP Terraform ou Spacelift.
- Times de app pedindo recursos (bancos, filas) com frequência: Crossplane para self-service.
