# eks-workloads

Terragrunt **unit template**, not a live unit — see
[`../eks-cluster/README.md`](../eks-cluster/README.md) for how a workload
account's `terragrunt.stack.hcl` instantiates it and how its lock file is
kept in sync.

No Terraform of its own. All resources live in
[`modules/eks-workloads`](../../modules/eks-workloads) (see its README for
inputs/outputs); `terragrunt.hcl` here only wires that module up via
`terraform { source = ... }`, reads the outputs of the `eks-cluster` unit
generated next to it (`../eks-cluster`, so the stack file must keep that
unit at `path = "eks-cluster"`) via a `dependency` block, and supplies the
rest of the module's inputs — backend/version constraints/common tags still
come from [`root.hcl`](../../root.hcl).

**Apply/destroy order matters**: this unit depends on `eks-cluster`, so
apply it after and destroy it *before* — see `modules/eks-cluster`'s README
for why. `terragrunt run --all apply`/`destroy` (or `make run-all-plan`/
`run-all-apply`) already sequences this correctly via the `dependency`
block; running the two units by hand, do `eks-cluster` first on apply,
`eks-workloads` first on destroy.
