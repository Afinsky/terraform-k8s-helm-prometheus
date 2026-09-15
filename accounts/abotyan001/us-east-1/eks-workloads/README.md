# eks-workloads

Thin Terragrunt wrapper: no Terraform of its own. All resources live in
[`modules/eks-workloads`](../../../../modules/eks-workloads) (see its README
for inputs/outputs); this directory only wires that module up via
`terraform { source = ... }` in `terragrunt.hcl`, reads
[`../eks-cluster`](../eks-cluster)'s outputs via a `dependency` block, and
supplies the rest of the module's inputs — backend/version
constraints/common tags still come from [`root.hcl`](../../../../root.hcl).

**Apply/destroy order matters**: this layer depends on `eks-cluster`, so
apply it after and destroy it *before* — see `modules/eks-cluster`'s README
for why. `terragrunt run --all apply`/`destroy` (or `make run-all-plan`/
`run-all-apply`) already sequences this correctly via the `dependency`
block; running the two layers by hand, do `eks-cluster` first on apply,
`eks-workloads` first on destroy.
