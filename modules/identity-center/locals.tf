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

  groups = toset(["platform-admins", "devops-admins", "developers", "qa-testers"])

  users = {
    aliaksei = {
      given_name  = "Aliaksei",
      family_name = "Admin",
      email       = local.alias_email.admin,
      group       = "devops-admins"
    }
    alice = {
      given_name  = "Alice",
      family_name = "Developer",
      email       = local.alias_email.alice,
      group       = "developers"
    }
    bob = {
      given_name  = "Bob",
      family_name = "Tester",
      email       = local.alias_email.bob,
      group       = "qa-testers"
    }
  }
}
