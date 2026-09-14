#-------------------------------------------------------------
# account.hcl
#
# - set common aws account variables
# - root.hcl in the repo root consolidates this file
#-------------------------------------------------------------

locals {
  aws_account_alias = "workloads-dev"
  aws_account_id    = "" # TODO: fill in after `make 01-identity-center apply` (see accounts.tf's `account_ids` output)

  # This account's own state bucket, created inside itself — not in abotyan001's
  # central "dev-me-terraform-state" — the first time `--backend-bootstrap` runs
  # a layer here. terraform-target is auto-deployed into every member account by
  # 01-identity-center/account_access_stackset.tf; it trusts only
  # terraform-management, hence state_profile below instead of "terraform"
  # directly. See root.hcl.
  state_bucket   = "workloads-dev-terraform-state"
  state_profile  = "terraform-management"
  state_role_arn = "arn:aws:iam::${local.aws_account_id}:role/terraform-target"
}
