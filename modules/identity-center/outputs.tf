output "sso_instance_arn" {
  value       = local.instance_arn
  description = "ARN of the IAM Identity Center instance."
}

output "identity_store_id" {
  value       = local.identity_store_id
  description = "Identity store ID, used by the 02-cluster stack."
}

output "user_emails" {
  value       = { for k, v in local.users : k => v.email }
  description = "Email aliases of the created users (all mail lands on var.email)."
}

output "account_ids" {
  value       = { for k, v in aws_organizations_account.this : k => v.id }
  description = "AWS account IDs of accounts created by this stack."
}

output "terraform_management_role_arn" {
  value       = aws_iam_role.terraform_management.arn
  description = "Assume this (via the \"terraform\" static IAM user) to reach terraform-target in any member account."
}

output "dns_zone_writer_role_arn" {
  value       = aws_iam_role.dns_zone_writer.arn
  description = "modules/develop assumes this (from any account) to write records into the Route53 zone below."
}

output "dns_zone_id" {
  value       = data.aws_route53_zone.this.zone_id
  description = "Route53 hosted zone ID for dns_zone_name, in this (the management) account."
}

output "dns_zone_name" {
  value       = local.zone_name
  description = "Domain this Organization's Route53 zone manages."
}
