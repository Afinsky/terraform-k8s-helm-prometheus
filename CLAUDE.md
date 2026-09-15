# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A personal AWS/EKS homelab managed with Terraform via Terragrunt. One AWS Organization rooted in `abotyan001` (the management account, running `01-identity-center`) plus member accounts vended by it (currently `workloads-dev`) that each get their own `eks-cluster` + `eks-workloads` layer pair — see `modules/` below. One region (`us-east-1`) throughout. **Everything on the cluster is applied directly from this repo** — VPC/EKS, IRSA controllers (aws-load-balancer-controller, external-dns, external-secrets), ingress-nginx, and the sample apps (`app.tf`, `online-boutique.tf`) are all live `helm_release`/`kubernetes_manifest` resources here, not GitOps-reconciled.

There is a sibling repo, `argo-k8s-helm` (checked out at `../argo-k8s-helm`), containing an ArgoCD-based GitOps setup for the same add-ons/apps — **but it's a parked experiment, not in use**. Nothing in this repo's Terraform references it. Don't assume resources described there reflect what's actually running; the source of truth for the live cluster is this repo's `.tf` files.

## Commands

```bash
make setup                       # mise install — pins terraform/terragrunt/tflint/etc, see mise.toml
make login                       # aws sso login --profile abotyan001-devops-admin
make lint                        # pre-commit run --all-files (fmt, validate, tflint, terraform-docs, conventional commits)

make <layer> <command>           # run one terragrunt command against one layer, e.g.:
make eks-cluster plan
make eks-workloads apply             # depends on eks-cluster - apply that one first
make 01-identity-center apply

make eks-cluster cmd CMD="console"   # anything without a Makefile shortcut: terragrunt run -- <cmd>
make eks-cluster state-list
make eks-cluster debug-plan          # --log-level debug
make run-all-plan                # plan every layer under accounts/abotyan001/us-east-1
make run-all-apply                   # dependency-ordered: eks-cluster before eks-workloads
make run-all-destroy                 # dependency-ordered: eks-workloads before eks-cluster
make destroy-safe                # eks-workloads, then wait for its LBs to clear, then eks-cluster

make clean                       # rm -rf all .terragrunt-cache / .terraform dirs
make force-provider-update       # rm all .terraform.lock.hcl (forces provider refresh)
```

`<layer>` is one of `01-identity-center`, `eks-cluster`, `eks-workloads` (mapped to `accounts/abotyan001/us-east-1/<layer>` in the Makefile). There is no single top-level `terraform`/`terragrunt` invocation — always go through `make <layer> ...` or `cd` into the layer directory and run `terragrunt` directly.

Other mise tasks (`mise run <task>`): `pre-commit`, `context` (point kubeconfig at the eks-cluster cluster), `docs`/`validate` (eks-cluster module), `docs-eks-workloads`/`validate-eks-workloads` (eks-workloads module).

## Architecture

**Terragrunt layering** (`root.hcl` at repo root, included by every `terragrunt.hcl`):
- Consolidates `global.hcl` (repo-wide vars), `account.hcl`, `region.hcl` (both under `accounts/abotyan001/`) into `inputs` for every layer.
- Configures the shared S3 remote-state backend (`dev-me-terraform-state`). The bucket is **never a terraform resource anywhere** — Terragrunt creates it itself (versioned, AES256-encrypted, public access blocked) the first time it's missing, via `--backend-bootstrap` baked into every Makefile command. Each layer's state key comes from its own sibling `state.hcl`, preserved verbatim from before Terragrunt adoption — not derived from path — so no state migration was needed when this repo moved to Terragrunt.
- No `generate "provider"` block: `eks-workloads`'s kubernetes/helm providers are wired off `eks-cluster`'s outputs (passed across the Terragrunt `dependency` boundary as plain string inputs, not `module.eks` references), which Terragrunt can't template statically, so `provider.tf` is hand-written and committed as-is (in `modules/eks-cluster/`/`modules/eks-workloads/`/`modules/identity-center/`, see below).

**`modules/`** (repo root): reusable Terraform modules, referenced from a layer's `terragrunt.hcl` via `terraform { source = "${get_repo_root()}/modules/<name>" }`. `modules/eks-cluster` (was `accounts/abotyan001/us-east-1/develop/`, then briefly `modules/develop`), `modules/eks-workloads` (split out of `modules/eks-cluster` — see below), and `modules/identity-center` (was `accounts/abotyan001/us-east-1/01-identity-center/`) — every layer directory now holds only `terragrunt.hcl` (the `source` + `inputs`), `state.hcl`, and the committed `.terraform.lock.hcl`. `modules/identity-center` isn't reused across accounts the way the other two are (it defines the Organization itself — inherently a single-instance stack, applied from exactly one account) — it was pulled out purely for consistency with the layer-vs-module split, not for reuse.

**`modules/eks-cluster` and `modules/eks-workloads` are both applied into more than one AWS account** — `accounts/abotyan001/us-east-1/{eks-cluster,eks-workloads}` and `accounts/workloads-dev/us-east-1/{eks-cluster,eks-workloads}` all point `terraform { source = ... }` at them. That's why the Route53 zone (`abotyan.click`) is handled specially: the zone stays in the management account (`modules/identity-center/dns.tf`'s `aws_iam_role.dns_zone_writer`, scoped to that one zone) rather than being duplicated per target account, and both `eks-cluster`'s ACM validation and `eks-workloads`'s `external-dns` reach it by assuming `dns-zone-writer` cross-account (`eks-cluster` via a second, aliased `aws.dns` Terraform provider; `external-dns` via its own runtime `--aws-assume-role-arn`) instead of writing to Route53 directly. `dns_zone_writer_role_arn`/`dns_zone_id`/`dns_zone_name` are global inputs (`global.hcl`) for this reason — one zone/role for the whole Organization, not a per-account value. `eks-cluster/eks-access-lab.tf`'s `lab_access_entries` filters out any permission set not assigned in the account it's currently applying into (see `permission_sets.tf`'s `account_patterns`) instead of erroring — not every account carries every permission set (`platform-admin` is deliberately management-account-only).

**`eks-cluster` vs `eks-workloads` split**: `eks-cluster` is pure AWS/VPC/EKS-control-plane/ACM — no Kubernetes or Helm provider anywhere in it. Everything that talks to the cluster's own API (IRSA controllers, ingress-nginx, sample apps, the PLAT-101 access-lab namespaces/RBAC) lives in `eks-workloads` instead, a separate Terragrunt layer that `dependency`s on `eks-cluster`'s outputs (`cluster_name`/`cluster_endpoint`/`cluster_certificate_authority_data`/`oidc_provider(_arn)`/`vpc_id`/`acm_certificate_arn`). This exists specifically for safe `terraform destroy`: destroying `eks-workloads` first, while the cluster and its controllers are still live, lets the AWS Load Balancer Controller actually deprovision any ALB/NLB it created before `eks-cluster`'s VPC/subnets get destroyed — doing both in one state risked an LB (and its ENIs) outliving the `helm_release` that owned it, orphaning it and blocking subnet deletion. `eks-workloads`'s `ingress_nginx`/`aws_load_balancer_controller` `helm_release`s set an explicit `timeout = 600` for the same reason (NLB/ALB target-group deregistration delay defaults to 300s, which can exceed the provider's own default timeout). `make destroy-safe` additionally polls `aws elbv2` between the two layers' destroys rather than trusting the timeout alone.

**The three layers**, applied in order, each with a distinct IAM identity rationale (see comments in each layer's `provider.tf`):
1. `01-identity-center` — AWS Organization + IAM Identity Center (SSO users/groups/permission sets), including the `devops-admin` permission set that becomes the `<account-alias>-devops-admin` SSO profile (e.g. `abotyan001-devops-admin`, `workloads-dev-devops-admin` — see `~/.aws/config`'s naming convention). Always applies as the static `terraform` IAM user, never `devops-admin` — this stack defines that role, so running it under its own not-yet-revocable STS token risks a self-lockout.
2. `eks-cluster` — a thin `terragrunt.hcl` wrapper around `modules/eks-cluster`: VPC, EKS cluster, ECR, ACM. Applies as `<account-alias>-devops-admin` — a consumer of the identity defined in layer 1, with no self-reference risk.
3. `eks-workloads` — a thin `terragrunt.hcl` wrapper around `modules/eks-workloads`, depending on `eks-cluster`'s outputs: IRSA-based controllers (aws-load-balancer-controller, external-dns, external-secrets), ingress-nginx, sample apps, and the PLAT-101 EKS access lab's Kubernetes-side half (`eks-access-lab.tf`: namespaced RBAC RoleBindings pairing with the AWS-IAM-side access entries created in `eks-cluster`'s own `eks-access-lab.tf`, consuming roles from `01-identity-center` by name pattern, not remote state or hardcoded ARNs). Also applies as `<account-alias>-devops-admin`.

**IRSA pattern**: every AWS-side controller (`external-dns.tf`, `external-secrets.tf`, `load-balancer-controller.tf`, all in `modules/eks-workloads`) follows the same shape — a dedicated IAM role trusting only that controller's ServiceAccount via OIDC, with a policy scoped as narrowly as the controller allows (e.g. `external-secrets.tf` only grants `GetSecretValue` on a naming-prefix, not account-wide `ListSecrets`; `external-dns.tf`'s role only gets `sts:AssumeRole` on `dns-zone-writer`, not direct Route53 access). Follow this pattern for any new controller rather than reusing an existing role or widening a policy.

**`k8s/manifests/*.yaml` + `app.tf`/`online-boutique.tf`** (in `modules/eks-workloads`): active, not legacy. Both `.tf` files apply real `kubernetes_manifest` resources using the same decode-and-apply pattern — `provider::kubernetes::manifest_decode_multi()` on raw upstream YAML read from `k8s/manifests/`, with `metadata.namespace` injected in Terraform since `kubernetes_manifest` needs it explicit and won't fall back to `default` the way `kubectl` does. `k8s/helm/*.yaml` are values files, also actively referenced — by `external-dns.tf`, `external-secrets.tf`, and `ingress-nginx.tf`'s `helm_release` blocks.

**mise.toml** is the single source of truth for CLI tool versions across *both* this repo's Terraform toolchain and the CLI tools used against the sibling `argo-k8s-helm` gitops tree (`helm`, `kubectl`, `kustomize`) — both are pinned here even though only the Terraform half is applied from this repo.

## Conventions

- **Never commit anything under `docs/`.** It's gitignored (`.gitignore`); those files are personal working notes, not repo deliverables. If new files show up there, they're untracked on purpose — don't `git add docs/` even under a broad `add -A`.
- Commit messages are enforced as Conventional Commits (`conventional-pre-commit` hook, `commit-msg` stage) and drive semantic-release (`.releaserc.yaml`, angular preset) — `fix:`/`feat:`/breaking changes trigger a version bump and `CHANGELOG.md` update; `chore:`/`docs:`/`test:` do not.
- `terraform-docs` regenerates `README.md` inputs/outputs tables (in `modules/identity-center/`, `modules/eks-cluster/`, and `modules/eks-workloads/`) between `BEGIN_TF_DOCS`/`END_TF_DOCS` markers on every commit (pre-commit hook + `.terraform-docs.yml`) — don't hand-edit those tables, edit the surrounding prose or the underlying `variables.tf`/`outputs.tf` instead. `modules/identity-center/README.md` has no markers at all — it's entirely hand-written prose, including the manual bootstrap steps (see its "Order of operations"). Every layer directory's own `README.md` (`01-identity-center/`, `eks-cluster/`, `eks-workloads/`) is hand-written prose too (no `.tf` there to document) and isn't touched by this hook.
- `tflint` in pre-commit is restricted to a specific rule allowlist (see `.pre-commit-config.yaml`) and excludes `modules/eks-cluster/unused/`.
- `pre-commit-terraform` is pinned to v1.88.0 on purpose — do not bump (see the comment in `.pre-commit-config.yaml` linking the upstream issue).
