output "parent_name_servers" {
  description = "COPIE ESTES 4 para o registrador: registros NS de lab.neosix.me (uma vez só)."
  value       = aws_route53_zone.parent.name_servers
}

output "zone_ids" {
  description = "IDs das zonas por ambiente (os stacks dos clusters leem via remote state para limitar o IAM)."
  value       = { for k, z in aws_route53_zone.env : k => z.zone_id }
}

output "zone_names" {
  description = "Nomes das zonas por ambiente (ex.: stg.lab.neosix.me)."
  value = { for k, z in aws_route53_zone.env : k => z.name }
}
