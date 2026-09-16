# eks-cluster.tfvars is a tflint-only fixture now — Terragrunt no longer reads it,
# real values live in terragrunt.hcl's `inputs` block. Keep both in sync.
config {
  varfile = ["eks-cluster.tfvars"]
}
