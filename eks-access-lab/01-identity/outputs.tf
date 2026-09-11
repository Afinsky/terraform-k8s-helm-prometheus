output "sso_instance_arn" {
  value       = local.instance_arn
  description = "ARN инстанса IAM Identity Center."
}

output "identity_store_id" {
  value       = local.identity_store_id
  description = "ID identity store, используется стеком 02-cluster."
}

output "user_emails" {
  value       = { for k, v in local.users : k => v.email }
  description = "Email-алиасы созданных пользователей (все письма приходят на var.email)."
}
