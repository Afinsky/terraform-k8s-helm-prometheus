# New AWS accounts vended into this Organization. Same rule as the rest of
# this stack (see provider.tf): applies under "terraform", not "lab-admin" —
# this is still the identity/org root layer, not a consumer of it.
# `aws_organizations_account` only works when the caller's credentials
# belong to the Organization's management account, which is this same
# account (organization.tf).
#
# Empty by default: add entries to local.accounts and apply. Example:
#
#   accounts = {
#     workloads-dev = {
#       name  = "workloads-dev"
#       email = "${local.email_parts[0]}+aws-workloads-dev@${local.email_parts[1]}"
#     }
#   }
#
# Email must be globally unique across all of AWS, not just this
# Organization — reuse the same +alias trick as local.alias_email, you
# can't register your real address twice.
locals {
  accounts = {
    workloads-dev = {
      name  = "workloads-dev"
      email = "${local.email_parts[0]}+aws-workloads-dev@${local.email_parts[1]}"
    }
  }
}

resource "aws_organizations_account" "this" {
  for_each = local.accounts

  name  = each.value.name
  email = each.value.email

  # Only removes the account from the Organization on `terraform destroy`,
  # doesn't close it - closing is a separate, much harder to undo action
  # (AWS gives you a short window to reverse it, then it's gone for good).
  # Flip to true deliberately, per-account, once you actually mean it.
  close_on_deletion = false

  tags = local.common_tags
}
