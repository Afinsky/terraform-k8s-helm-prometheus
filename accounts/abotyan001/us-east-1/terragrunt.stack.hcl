#-------------------------------------------------------------
# terragrunt.stack.hcl
#
# The management account: only identity-center, instantiated from
# units/identity-center. No workload infra runs here - EKS lives in the
# workload accounts' own stacks (e.g. accounts/workloads-dev/us-east-1/).
#
# `terragrunt stack generate` expands this into .terragrunt-stack/identity-center/
# next to this file - gitignored, never edited by hand. Every workload
# account's eks-* units depend on that generated directory, so the Makefile
# and CI generate every account's stack, not just the one being run.
#-------------------------------------------------------------

unit "identity-center" {
  source = "${get_repo_root()}/units/identity-center"
  # eks-* units' dependency "identity_center" points at this exact path, and
  # the Makefile's sync-locks expects it to match the units/ directory name
  path = "identity-center"

  values = {
    environment = "dev"
    email       = "a.afinsky@gmail.com"
  }
}
