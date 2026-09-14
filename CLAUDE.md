# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A personal AWS/EKS homelab managed with Terraform via Terragrunt. One AWS Organization rooted in `abotyan001` (the management account, running `01-identity-center`) plus member accounts vended by it (currently `workloads-dev`) that each get their own `develop` layer — see `modules/` below. One region (`us-east-1`) throughout. **Everything on the cluster is applied directly from this repo** — VPC/EKS, IRSA controllers (aws-load-balancer-controller, external-dns, external-secrets), ingress-nginx, and the sample apps (`app.tf`, `online-boutique.tf`) are all live `helm_release`/`kubernetes_manifest` resources here, not GitOps-reconciled.

There is a sibling repo, `argo-k8s-helm` (checked out at `../argo-k8s-helm`), containing an ArgoCD-based GitOps setup for the same add-ons/apps — **but it's a parked experiment, not in use**. Nothing in this repo's Terraform references it. Don't assume resources described there reflect what's actually running; the source of truth for the live cluster is this repo's `.tf` files.

## Commands

```bash
make setup                       # mise install — pins terraform/terragrunt/tflint/etc, see mise.toml
make login                       # aws sso login --profile lab-admin
make lint                        # pre-commit run --all-files (fmt, validate, tflint, terraform-docs, conventional commits)

make <layer> <command>           # run one terragrunt command against one layer, e.g.:
make eks-cluster plan
make 01-identity-center apply

make eks-cluster cmd CMD="console"   # anything without a Makefile shortcut: terragrunt run -- <cmd>
make eks-cluster state-list
make eks-cluster debug-plan          # --log-level debug
make run-all-plan                # plan every layer under accounts/abotyan001/us-east-1
make run-all-apply

make clean                       # rm -rf all .terragrunt-cache / .terraform dirs
make force-provider-update       # rm all .terraform.lock.hcl (forces provider refresh)
```

`<layer>` is one of `01-identity-center`, `develop` (mapped to `accounts/abotyan001/us-east-1/<layer>` in the Makefile). There is no single top-level `terraform`/`terragrunt` invocation — always go through `make <layer> ...` or `cd` into the layer directory and run `terragrunt` directly.

Other mise tasks (`mise run <task>`): `pre-commit`, `context` (point kubeconfig at the develop cluster), `docs` (regenerate `modules/develop/README.md` via terraform-docs), `validate` (fmt-check + validate + tflint on `modules/develop` only).

## Architecture

**Terragrunt layering** (`root.hcl` at repo root, included by every `terragrunt.hcl`):
- Consolidates `global.hcl` (repo-wide vars), `account.hcl`, `region.hcl` (both under `accounts/abotyan001/`) into `inputs` for every layer.
- Configures the shared S3 remote-state backend (`dev-me-terraform-state`). The bucket is **never a terraform resource anywhere** — Terragrunt creates it itself (versioned, AES256-encrypted, public access blocked) the first time it's missing, via `--backend-bootstrap` baked into every Makefile command. Each layer's state key comes from its own sibling `state.hcl`, preserved verbatim from before Terragrunt adoption — not derived from path — so no state migration was needed when this repo moved to Terragrunt.
- No `generate "provider"` block: `develop`'s kubernetes/helm providers are wired off live `module.eks` outputs, which Terragrunt can't template statically, so `provider.tf` is hand-written and committed as-is (in `modules/develop/`/`modules/identity-center/`, see below).

**`modules/`** (repo root): reusable Terraform modules, referenced from a layer's `terragrunt.hcl` via `terraform { source = "${get_repo_root()}/modules/<name>" }`. `modules/develop` (was `accounts/abotyan001/us-east-1/develop/`) and `modules/identity-center` (was `accounts/abotyan001/us-east-1/01-identity-center/`) — every layer directory now holds only `terragrunt.hcl` (the `source` + `inputs`), `state.hcl`, and the committed `.terraform.lock.hcl`. `modules/identity-center` isn't reused across accounts the way `modules/develop` is (it defines the Organization itself — inherently a single-instance stack, applied from exactly one account) — it was pulled out purely for consistency with `develop`'s layer-vs-module split, not for reuse.

**`modules/develop` is applied into more than one AWS account** — `accounts/abotyan001/us-east-1/develop` and `accounts/workloads-dev/us-east-1/develop` both point `terraform { source = ... }` at it. That's why its Route53 zone (`abotyan.click`) is handled specially: the zone stays in the management account (`modules/identity-center/dns.tf`'s `aws_iam_role.dns_zone_writer`, scoped to that one zone) rather than being duplicated per target account, and both ACM validation and `external-dns` reach it by assuming `dns-zone-writer` cross-account (a second, aliased `aws.dns` provider in `modules/develop/provider.tf`) instead of writing to Route53 directly. `dns_zone_writer_role_arn`/`dns_zone_id`/`dns_zone_name` are global inputs (`global.hcl`) for this reason — one zone/role for the whole Organization, not a per-account value. `eks-access-lab.tf`'s `lab_access_entries` filters out any permission set not assigned in the account it's currently applying into (see `permission_sets.tf`'s `account_patterns`) instead of erroring — not every account carries every permission set (`platform-admin` is deliberately management-account-only).

**The two layers**, applied in order, each with a distinct IAM identity rationale (see comments in each layer's `provider.tf`):
1. `01-identity-center` — AWS Organization + IAM Identity Center (SSO users/groups/permission sets), including the `PlatformAdmin` permission set that becomes the `lab-admin` SSO profile. Always applies as the static `terraform` IAM user, never `lab-admin` — this stack defines that role, so running it under its own not-yet-revocable STS token risks a self-lockout.
2. `develop` — a thin `terragrunt.hcl` wrapper around `modules/develop`: VPC, EKS cluster, IRSA-based controllers (aws-load-balancer-controller, external-dns, external-secrets), ECR, ACM, and the PLAT-101 EKS access lab (`eks-access-lab.tf`: namespaced RBAC via IAM Identity Center access entries for `payments-dev`/`payments-prod`/`search-dev`, consuming roles from `01-identity-center` by name pattern, not remote state or hardcoded ARNs). Applies as `lab-admin` — a consumer of the identity defined in layer 1, with no self-reference risk.

**IRSA pattern**: every AWS-side controller (`external-dns.tf`, `external-secrets.tf`, `load-balancer-controller.tf`) follows the same shape — a dedicated IAM role trusting only that controller's ServiceAccount via OIDC, with a policy scoped as narrowly as the controller allows (e.g. `external-secrets.tf` only grants `GetSecretValue` on a naming-prefix, not account-wide `ListSecrets`; `external-dns.tf` scopes to the one Route53 zone this repo manages). Follow this pattern for any new controller rather than reusing an existing role or widening a policy.

**`k8s/manifests/*.yaml` + `app.tf`/`online-boutique.tf`**: active, not legacy. Both `.tf` files apply real `kubernetes_manifest` resources using the same decode-and-apply pattern — `provider::kubernetes::manifest_decode_multi()` on raw upstream YAML read from `k8s/manifests/`, with `metadata.namespace` injected in Terraform since `kubernetes_manifest` needs it explicit and won't fall back to `default` the way `kubectl` does. `k8s/helm/*.yaml` are values files, also actively referenced — by `external-dns.tf`, `external-secrets.tf`, and `ingress-nginx.tf`'s `helm_release` blocks.

**mise.toml** is the single source of truth for CLI tool versions across *both* this repo's Terraform toolchain and the CLI tools used against the sibling `argo-k8s-helm` gitops tree (`helm`, `kubectl`, `kustomize`) — both are pinned here even though only the Terraform half is applied from this repo.

## Conventions

- **Never commit anything under `docs/`.** It's gitignored (`.gitignore`); those files are personal working notes, not repo deliverables. If new files show up there, they're untracked on purpose — don't `git add docs/` even under a broad `add -A`.
- Commit messages are enforced as Conventional Commits (`conventional-pre-commit` hook, `commit-msg` stage) and drive semantic-release (`.releaserc.yaml`, angular preset) — `fix:`/`feat:`/breaking changes trigger a version bump and `CHANGELOG.md` update; `chore:`/`docs:`/`test:` do not.
- `terraform-docs` regenerates `README.md` inputs/outputs tables (in `modules/identity-center/` and `modules/develop/`) between `BEGIN_TF_DOCS`/`END_TF_DOCS` markers on every commit (pre-commit hook + `.terraform-docs.yml`) — don't hand-edit those tables, edit the surrounding prose or the underlying `variables.tf`/`outputs.tf` instead. `modules/identity-center/README.md` has no markers at all — it's entirely hand-written prose, including the manual bootstrap steps (see its "Order of operations"). Both `01-identity-center/` and `develop/` layer directories' own `README.md`s are hand-written prose too (no `.tf` there to document) and aren't touched by this hook.
- `tflint` in pre-commit is restricted to a specific rule allowlist (see `.pre-commit-config.yaml`) and excludes `modules/develop/unused/`.
- `pre-commit-terraform` is pinned to v1.88.0 on purpose — do not bump (see the comment in `.pre-commit-config.yaml` linking the upstream issue).
