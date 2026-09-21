output "sso_instance_arn" {
  value       = local.instance_arn
  description = "ARN of the IAM Identity Center instance."
}

output "identity_store_id" {
  value       = local.identity_store_id
  description = "Identity store ID for this Identity Center instance. Not currently consumed by any other layer."
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
  description = "modules/eks-cluster assumes this (from any account) to write records into the Route53 zone below."
}

output "dns_zone_id" {
  value       = data.aws_route53_zone.this.zone_id
  description = "Route53 hosted zone ID for dns_zone_name, in this (the management) account."
}

output "dns_zone_name" {
  value       = local.zone_name
  description = "Domain this Organization's Route53 zone manages."
}

output "github_actions_plan_role_arn" {
  value       = aws_iam_role.github_actions_plan.arn
  description = ".github/workflows/plan.yml assumes this via OIDC (no stored credentials) to plan the management account's own layers, and chains through it to assume github-actions-plan-target (account_access_stackset.tf) in every member account."
}

output "secrets_reader_role_arn" {
  value       = aws_iam_role.secrets_reader.arn
  description = "modules/eks-workloads' external-secrets assumes this (from any account) to read app secrets out of Secrets Manager here."
}
