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
