# Zona pai: o registrador delega SÓ este subdomínio para a AWS. O resto do domínio não muda.
resource "aws_route53_zone" "parent" {
  name    = var.domain
  comment = "Lab: zona pai delegada pelo registrador. Filhas por ambiente."
}

# Uma zona por ambiente. Por quê: o external-dns e o cert-manager do stg recebem uma role
# IAM que só escreve em stg.<domain>. Um bug ou credencial vazada no stg não toca em prod.
resource "aws_route53_zone" "env" {
  for_each = toset(var.environments)

  name    = "${each.key}.${var.domain}"
  comment = "Lab: registros do ambiente ${each.key} (external-dns e cert-manager do cluster eks-${each.key})."
}

# Delegação pai -> filha (os NS da filha publicados na pai). Sem isto a filha existe mas
# ninguém na internet a encontra.
resource "aws_route53_record" "delegation" {
  for_each = aws_route53_zone.env

  zone_id = aws_route53_zone.parent.zone_id
  name    = each.value.name
  type    = "NS"
  ttl     = 300
  records = each.value.name_servers
}

# CAA: só a Let's Encrypt pode emitir certificados para estes nomes. Se alguém tentar
# emitir em outra CA (credencial vazada, erro), a CA é obrigada a recusar.
resource "aws_route53_record" "caa" {
  zone_id = aws_route53_zone.parent.zone_id
  name    = var.domain
  type    = "CAA"
  ttl     = 3600
  records = ["0 issue \"letsencrypt.org\"", "0 issuewild \"letsencrypt.org\""]
}
