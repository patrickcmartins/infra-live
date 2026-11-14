# aws/bootstrap (aplicado por humano, fora do Atlantis)

Cria a fundação que o resto precisa para existir:
bucket de state, OIDC do GitHub, a role `terraform-deployer` com o usuário `atlantis-local`, e o budget.

```bash
aws configure sso                       # perfil admin via IAM Identity Center
export AWS_PROFILE=admin
terraform init && terraform apply -var budget_email=voce@exemplo.com
# depois: descomente o backend "s3" em versions.tf
terraform init -migrate-state
aws iam create-access-key --user-name atlantis-local   # -> atlantis-server/secrets/aws/credentials
```

**Por que fora do Atlantis?** Ele cria a identidade que o Atlantis usa (o problema do ovo e da galinha) e mexe em IAM,
que é o escopo mais sensível da conta. Em empresa isso vive num repo `landing-zone`
(AWS Organizations, Control Tower/AFT) com aprovação de segurança.
