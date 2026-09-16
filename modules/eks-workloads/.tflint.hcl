# eks-workloads.tfvars is a tflint-only fixture - Terragrunt sets the real
# values (repo_root/aws_account_id) and reads the modules/eks-cluster
# dependency outputs for the rest. Keep both in sync.
config {
  varfile = ["eks-workloads.tfvars"]
}
