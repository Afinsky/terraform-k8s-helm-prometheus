# identity.tfvars is a tflint-only fixture now — Terragrunt no longer reads it,
# real values live in terragrunt.hcl's `inputs` block. Keep both in sync.
config {
  varfile = ["identity.tfvars"]
}

plugin "aws" {
  enabled = true
  version = "0.44.0"
  source  = "github.com/terraform-linters/tflint-ruleset-aws"
}
