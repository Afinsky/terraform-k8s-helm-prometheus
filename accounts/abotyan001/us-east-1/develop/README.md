# develop

Thin Terragrunt wrapper: no Terraform of its own. All resources live in
[`modules/develop`](../../../../modules/develop) (see its README for
inputs/outputs); this directory only wires that module up via
`terraform { source = ... }` in `terragrunt.hcl` and supplies its inputs —
backend/version constraints/common tags still come from
[`root.hcl`](../../../../root.hcl).
