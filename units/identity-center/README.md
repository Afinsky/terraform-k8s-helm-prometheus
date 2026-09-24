# identity-center

Terragrunt **unit template**, not a live unit: never run `terragrunt` in this
directory. Instantiated exactly once, by the management account's
[`terragrunt.stack.hcl`](../../accounts/abotyan001/us-east-1/terragrunt.stack.hcl),
into `accounts/abotyan001/us-east-1/.terragrunt-stack/identity-center/` — see
[`../eks-cluster/README.md`](../eks-cluster/README.md) for how generation and
the shared lock file work.

No Terraform of its own. All resources live in
[`modules/identity-center`](../../modules/identity-center) (see its README for
inputs/outputs, and the "Order of operations" section for the manual bootstrap
steps this stack needs); `terragrunt.hcl` here only wires that module up via
`terraform { source = ... }` and supplies its inputs — backend/version
constraints/common tags still come from [`root.hcl`](../../root.hcl).
