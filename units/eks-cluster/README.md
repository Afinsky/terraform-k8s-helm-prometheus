# eks-cluster

Terragrunt **unit template**, not a live unit: never run `terragrunt` in this
directory. Each workload account instantiates it from its own
`accounts/<alias>/us-east-1/terragrunt.stack.hcl` (see
[`workloads-dev`'s](../../accounts/workloads-dev/us-east-1/terragrunt.stack.hcl)),
which `terragrunt stack generate` copies into that account's
`.terragrunt-stack/eks-cluster/` together with the account's `values`
(`profile`, `environment`, `vpc`).

No Terraform of its own. All resources live in
[`modules/eks-cluster`](../../modules/eks-cluster) (see its README for
inputs/outputs); `terragrunt.hcl` here only wires that module up via
`terraform { source = ... }` and maps `values.*` and
`01-identity-center`'s outputs onto its inputs — backend/version
constraints/common tags still come from [`root.hcl`](../../root.hcl).

`.terraform.lock.hcl` here is the one lock file every account's generated
copy starts from. `make <layer> <command>` copies any change `init` makes to
it back here, so commit it like any other lock file.
