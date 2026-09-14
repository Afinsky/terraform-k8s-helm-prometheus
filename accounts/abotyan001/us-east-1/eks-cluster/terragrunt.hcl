#-------------------------------------------------------------
# terragrunt.hcl
#
# - wire up the modules/eks-cluster module and configure its inputs (was develop.tfvars —
#   the tflint fixture in modules/eks-cluster/ still keeps that filename)
# - backend key comes from state.hcl (see root.hcl)
#-------------------------------------------------------------

include {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  # Local path, not a versioned/remote source: this module isn't published outside this
  # repo. It is reused, though — see accounts/workloads-dev/us-east-1/eks-cluster/terragrunt.hcl,
  # the same module applied into a different account.
  source = "${get_repo_root()}/modules/eks-cluster"
}

inputs = {
  profile     = "lab-admin" #"terraform"
  environment = "dev"
  region      = "us-east-1"
  repo_root   = get_repo_root()

  # PLAT-101 Phase 3: EKS public API endpoint is restricted to this IP.
  # Refresh it before applying if it's stale: curl -s https://checkip.amazonaws.com
  my_ip_cidr = "83.175.181.227/32"

  vpc = {
    homelab = {
      cidr             = "10.30.0.0/16"
      azs              = ["us-east-1c", "us-east-1f"]
      private_subnets  = ["10.30.10.0/24", "10.30.11.0/24"]
      public_subnets   = ["10.30.20.0/24", "10.30.21.0/24"]
      database_subnets = ["10.30.30.0/24", "10.30.31.0/24"]
    }
  }
}
