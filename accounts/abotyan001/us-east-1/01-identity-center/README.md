# 01-identity-center

Thin Terragrunt wrapper: no Terraform of its own. All resources live in
[`modules/identity-center`](../../../../modules/identity-center) (see its
README for inputs/outputs, and the "Order of operations" section for the
manual bootstrap steps this stack needs); this directory only wires that
module up via `terraform { source = ... }` in `terragrunt.hcl` and supplies
its inputs — backend/version constraints/common tags still come from
[`root.hcl`](../../../../root.hcl).
