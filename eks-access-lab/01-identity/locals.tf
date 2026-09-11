locals {
  common_tags = merge(
    {
      "client"      = "K8S practice"
      "project"     = "eks-access-lab"
      "environment" = var.environment
      "owner"       = "me"
      "Terraform"   = "true"
    }
  )

  project_name  = "eks-access-lab"
  resource_name = "${var.environment}-${local.project_name}"

  email_parts = split("@", var.email)
  alias_email = {
    for suffix in ["admin", "alice", "bob"] :
    suffix => "${local.email_parts[0]}+${suffix}@${local.email_parts[1]}"
  }

  groups = toset(["platform-admins", "payments-devs", "search-devs"])

  users = {
    aliaksei = { given_name = "Aliaksei", family_name = "Admin", email = local.alias_email.admin, group = "platform-admins" }
    alice    = { given_name = "Alice", family_name = "Payments", email = local.alias_email.alice, group = "payments-devs" }
    bob      = { given_name = "Bob", family_name = "Search", email = local.alias_email.bob, group = "search-devs" }
  }

  # One team = one group = one permission set = one IAM role.
  # Permission set names are fixed (not resource_name-prefixed):
  # Phase 3 (02-cluster) looks them up by the regex "AWSReservedSSO_EKSDev-...".
  teams = {
    payments = { group = "payments-devs", permission_set = "EKSDev-Payments" }
    search   = { group = "search-devs", permission_set = "EKSDev-Search" }
  }
}
