#data "aws_caller_identity" "current" {}

# Live list of every account in the Organization (management account
# included) — lets permission_sets.tf match accounts by name pattern
# instead of hardcoding IDs. Re-evaluated on every apply, so an account
# vended later by accounts.tf is picked up automatically by any permission
# set whose account_patterns match its name.
data "aws_organizations_organizational_unit_descendant_accounts" "all" {
  parent_id = aws_organizations_organization.this.roots[0].id
}

# ------------------------------------------------------------------
# Between apply #1 (organization.tf) and apply #2 (this data source)
# a manual step is required: enable IAM Identity Center in the console.
# The AWS provider has no resource that enables Identity Center as an
# organization instance, so this data source would otherwise find nothing.
# See README.md.
# ------------------------------------------------------------------
data "aws_ssoadmin_instances" "this" {}
