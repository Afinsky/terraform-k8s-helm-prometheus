# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A personal AWS/EKS homelab managed with Terraform via Terragrunt. One AWS account (`abotyan001`), one region (`us-east-1`), three sequential layers. In-cluster Kubernetes objects that need Terraform's live `module.eks` outputs (kubernetes/helm providers) are applied directly from this repo; the ArgoCD-managed GitOps tree (ingress-nginx, external-dns/-secrets Applications, sample apps like Online Boutique) lives in a **separate** repo, `argo-k8s-helm` (checked out as a sibling at `../argo-k8s-helm`), which this repo's Terraform does not reference except by a hand-maintained inline heredoc (see Architecture below).

## Commands

```bash
make setup                       # mise install — pins terraform/terragrunt/tflint/etc, see mise.toml
make login                       # aws sso login --profile lab-admin
make lint                        # pre-commit run --all-files (fmt, validate, tflint, terraform-docs, conventional commits)

make <layer> <command>           # run one terragrunt command against one layer, e.g.:
make develop plan
make 01-identity-center apply
make 00-bootstrap output

make develop cmd CMD="console"   # anything without a Makefile shortcut: terragrunt run -- <cmd>
make develop state-list
make develop debug-plan          # --log-level debug
make run-all-plan                # plan every layer under accounts/abotyan001/us-east-1
make run-all-apply

make clean                       # rm -rf all .terragrunt-cache / .terraform dirs
make force-provider-update       # rm all .terraform.lock.hcl (forces provider refresh)
```

`<layer>` is one of `00-bootstrap`, `01-identity-center`, `develop` (mapped to `accounts/abotyan001/us-east-1/<layer>` in the Makefile). There is no single top-level `terraform`/`terragrunt` invocation — always go through `make <layer> ...` or `cd` into the layer directory and run `terragrunt` directly.

Other mise tasks (`mise run <task>`): `pre-commit`, `context` (point kubeconfig at the develop cluster), `docs` (regenerate `develop/README.md` via terraform-docs), `validate` (fmt-check + validate + tflint on `develop` only).

## Architecture

**Terragrunt layering** (`root.hcl` at repo root, included by every `terragrunt.hcl`):
- Consolidates `global.hcl` (repo-wide vars), `account.hcl`, `region.hcl` (both under `accounts/abotyan001/`) into `inputs` for every layer.
- Configures the shared S3 remote-state backend (`dev-me-terraform-state`, bucket created once by `00-bootstrap`, never by Terragrunt itself). Each layer's state key comes from its own sibling `state.hcl`, preserved verbatim from before Terragrunt adoption — not derived from path — so no state migration was needed when this repo moved to Terragrunt.
- No `generate "provider"` block: `develop`'s kubernetes/helm providers are wired off live `module.eks` outputs, which Terragrunt can't template statically, so `provider.tf` in each layer is hand-written and committed as-is.

**The three layers**, applied in order, each with a distinct IAM identity rationale (see comments in each layer's `provider.tf`):
1. `00-bootstrap` — the S3 state bucket. Local backend (nothing to point at yet).
2. `01-identity-center` — AWS Organization + IAM Identity Center (SSO users/groups/permission sets), including the `PlatformAdmin` permission set that becomes the `lab-admin` SSO profile. Always applies as the static `terraform` IAM user, never `lab-admin` — this stack defines that role, so running it under its own not-yet-revocable STS token risks a self-lockout.
3. `develop` — VPC, EKS cluster, IRSA-based controllers (aws-load-balancer-controller, external-dns, external-secrets), ECR, ACM, and the PLAT-101 EKS access lab (`eks-access-lab.tf`: namespaced RBAC via IAM Identity Center access entries for `payments-dev`/`payments-prod`/`search-dev`, consuming roles from `01-identity-center` by name pattern, not remote state or hardcoded ARNs). Applies as `lab-admin` — a consumer of the identity defined in layer 2, with no self-reference risk.

**IRSA pattern**: every AWS-side controller (`external-dns.tf`, `external-secrets.tf`, `load-balancer-controller.tf`) follows the same shape — a dedicated IAM role trusting only that controller's ServiceAccount via OIDC, with a policy scoped as narrowly as the controller allows (e.g. `external-secrets.tf` only grants `GetSecretValue` on a naming-prefix, not account-wide `ListSecrets`; `external-dns.tf` scopes to the one Route53 zone this repo manages). Follow this pattern for any new controller rather than reusing an existing role or widening a policy.

**`k8s/manifests/*.yaml` + `app.tf`/`online-boutique.tf`**: legacy pre-ArgoCD path, currently unused (both `.tf` files are fully commented out) but not deleted — kept as a record of the `provider::kubernetes::manifest_decode_multi()` decode-and-apply pattern (raw upstream YAML on disk, namespace injected in Terraform since `kubernetes_manifest` needs an explicit `metadata.namespace` and won't fall back to `default` the way `kubectl` does). Sample apps and addons are managed via ArgoCD in the separate `argo-k8s-helm` repo instead. `k8s/helm/*.yaml` are values files with no current Terraform reference either.

**mise.toml** is the single source of truth for CLI tool versions across *both* this repo's Terraform toolchain and the CLI tools used against the sibling `argo-k8s-helm` gitops tree (`helm`, `kubectl`, `kustomize`) — both are pinned here even though only the Terraform half is applied from this repo.

## Conventions

- **Never commit anything under `docs/`.** It's gitignored (`.gitignore`); those files are personal working notes, not repo deliverables. If new files show up there, they're untracked on purpose — don't `git add docs/` even under a broad `add -A`.
- Commit messages are enforced as Conventional Commits (`conventional-pre-commit` hook, `commit-msg` stage) and drive semantic-release (`.releaserc.yaml`, angular preset) — `fix:`/`feat:`/breaking changes trigger a version bump and `CHANGELOG.md` update; `chore:`/`docs:`/`test:` do not.
- `terraform-docs` regenerates each layer's `README.md` inputs/outputs tables between `BEGIN_TF_DOCS`/`END_TF_DOCS` markers on every commit (pre-commit hook + `.terraform-docs.yml`) — don't hand-edit those tables, edit the surrounding prose or the underlying `variables.tf`/`outputs.tf` instead.
- `tflint` in pre-commit is restricted to a specific rule allowlist (see `.pre-commit-config.yaml`) and excludes `accounts/abotyan001/us-east-1/develop/unused/`.
- `pre-commit-terraform` is pinned to v1.88.0 on purpose — do not bump (see the comment in `.pre-commit-config.yaml` linking the upstream issue).
