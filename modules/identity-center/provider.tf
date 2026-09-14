# This stack always runs under "terraform" (static IAM user,
# AdministratorAccess) - never "lab-admin". Not just for the very first
# bootstrap apply: this stack is the one that DEFINES the "lab-admin" SSO
# profile's own role, PlatformAdmin - its permission set, its managed
# policy, its account assignment (sso.tf). Applying this code under
# lab-admin would mean that role editing its own definition through itself:
# a bad change here (wrong principal_id, a dropped policy attachment) can
# still apply successfully under an already-issued STS token (AWS doesn't
# revoke those retroactively), then lock out the *next* `aws sso login
# --profile lab-admin` - and you'd have to fall back to "terraform" to fix
# it anyway. So skip the round-trip and just always use it here.
#
# "lab-admin" is for stacks that CONSUME this identity instead of defining
# it - e.g. environments/eks-cluster, or any future per-account workload stack.
# Those don't touch PlatformAdmin's own definition, so there's no
# self-reference risk.
provider "aws" {
  region                   = var.region
  shared_config_files      = ["$HOME/.aws/config"]
  shared_credentials_files = ["$HOME/.aws/credentials"]
  profile                  = var.profile

  # guard against applying against the wrong AWS account/profile
  allowed_account_ids = [var.aws_account_id]
}
