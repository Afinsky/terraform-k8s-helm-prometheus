# terraform-k8s-helm-prometheus

A personal AWS/EKS homelab, provisioned with Terraform via Terragrunt. Used to practice
production-shaped patterns — IAM Identity Center SSO, IRSA, Terragrunt layering,
namespaced Kubernetes RBAC — on a single low-cost account, not to run anything real.

One AWS account (`abotyan001`), one region (`us-east-1`), two Terragrunt layers.
Everything on the cluster (VPC, EKS, ingress-nginx, external-dns, external-secrets, sample
apps) is applied directly from this repo — there is no GitOps/ArgoCD reconciliation involved
right now (see [GitOps status](#gitops-status-parked) below).

## Architecture

```
AWS account: abotyan001 (417886991962), region: us-east-1
│
├─ 01-identity-center   AWS Organization + IAM Identity Center (SSO)
│                        groups/users/permission sets. Applies as the
│                        static "terraform" IAM user.
│
└─ develop               VPC, EKS cluster, IRSA controllers, ECR, ACM,
                          namespaced RBAC lab, sample apps. Applies as
                          "lab-admin" — an SSO role defined by the layer above.
```

Layers are applied in that order: `01-identity-center` first creates the `PlatformAdmin`
permission set that becomes the `lab-admin` SSO profile everything else runs as.

### Terragrunt layering

- [`root.hcl`](root.hcl) (repo root, included by every `terragrunt.hcl`) consolidates
  [`global.hcl`](global.hcl) (project name, common tags), `accounts/abotyan001/account.hcl`
  (account ID/alias) and `accounts/abotyan001/us-east-1/region.hcl` into `inputs` for every layer.
- It also configures the shared S3 state backend (`dev-me-terraform-state`). The bucket is
  **never a terraform resource anywhere** — Terragrunt creates it itself (versioned,
  AES256-encrypted, public access blocked) the first time it's missing, via
  `--backend-bootstrap` baked into every `Makefile` command. Each layer's own state key comes
  from a sibling `state.hcl`, so migrating to Terragrunt didn't require moving any state.
- There's no `generate "provider"` block: `develop`'s kubernetes/helm providers need live
  `module.eks` outputs, which Terragrunt can't template statically, so `provider.tf` is a
  hand-written, committed file (in `modules/develop/` — see below).
- Both layers are thin wrappers: each `terragrunt.hcl` has no Terraform of its own, just a
  `terraform { source = "${get_repo_root()}/modules/<name>" }` block plus `inputs`. Only
  `modules/develop` is actually reused across accounts, though (`modules/identity-center` was
  split out purely for the layer/module consistency, not because anything else points at it —
  it defines the Organization itself, so it's inherently single-instance).

### `01-identity-center`

Creates the AWS Organization and IAM Identity Center: three users (`aliaksei`, `alice`, `bob`),
three groups, and the permission sets/account assignments that turn into SSO roles:

- **`PlatformAdmin`** — `AdministratorAccess` on the whole account, assigned to `platform-admins`.
  Becomes the `lab-admin` SSO profile.
- **`EKSDev-Payments`** / **`EKSDev-Search`** — minimal IAM (just enough to find the cluster),
  assigned to `payments-devs`/`search-devs`. Real Kubernetes access comes later, from EKS access
  entries + RBAC defined in `develop` — not from IAM.

Always applies as the static `terraform` IAM user, never `lab-admin`: this stack defines that
role, so running it under its own not-yet-revocable STS token risks a self-lockout (see the
comment in `provider.tf`).

### `develop`

- **VPC** (`terraform-aws-modules/vpc/aws`) — single NAT gateway, flow logs optional.
- **EKS** (`terraform-aws-modules/eks/aws`) — one SPOT-capacity managed node group,
  access-entries-only auth (no `aws-auth` ConfigMap).
- **IRSA controllers** — `aws-load-balancer-controller`, `external-dns`, `external-secrets`.
  Each gets a dedicated IAM role trusting only its own ServiceAccount via OIDC, with a policy
  scoped as narrowly as the controller allows (e.g. `external-secrets` only gets
  `GetSecretValue` on a naming-prefix, not account-wide `ListSecrets`). New controllers should
  follow the same shape rather than reuse or widen an existing role.
- **ingress-nginx** — fronted by the load balancer controller.
- **ACM** + **Route53** — one wildcard cert, DNS validation.
- **ECR** — one repository.
- **PLAT-101 EKS access lab** (`eks-access-lab.tf`) — namespaced RBAC via IAM Identity Center
  access entries for `payments-dev`/`payments-prod`/`search-dev`, consuming the SSO roles from
  `01-identity-center` by name pattern (not remote state, not hardcoded ARNs).
- **Sample apps** — a small photo app (`app.tf`) and Online Boutique
  (`online-boutique.tf`, [GoogleCloudPlatform/microservices-demo](https://github.com/GoogleCloudPlatform/microservices-demo)),
  applied as `kubernetes_manifest` from raw upstream YAML in `k8s/manifests/` (namespace
  injected in Terraform — `kubernetes_manifest` needs it explicit, unlike `kubectl`). These
  exist to practice a real multi-service topology, which is also where the "prometheus" in this
  repo's name comes from — no Prometheus/Grafana stack is actually deployed yet.

Applies as `lab-admin` — a consumer of the identity `01-identity-center` defines, with no
self-reference risk.

## GitOps status: parked

A sibling repo, [`argo-k8s-helm`](https://github.com/Afinsky/argo-k8s-helm) (checked out at
`../argo-k8s-helm`), contains an ArgoCD-based GitOps setup for these same add-ons and apps.
**It's a parked experiment, not in use.** This repo's Terraform is the sole source of truth for
the live cluster; nothing here references the gitops repo.

## Repository layout

```
root.hcl                          # Terragrunt root config: backend, version constraints, inputs
global.hcl                        # project_name, common_tags, dns_zone_* (see "develop" above)
modules/
  identity-center/                # all of layer 1's Terraform — see above
  develop/                        # all of layer 2's Terraform — see above
    unused/                       # archived alternative node-group configs (not compiled)
accounts/
  abotyan001/                     # the management account
    account.hcl                   # aws_account_alias, aws_account_id
    us-east-1/
      region.hcl                  # aws_region
      01-identity-center/         # layer 1 — terragrunt.hcl + state.hcl only, wires up modules/identity-center
      develop/                    # layer 2 — terragrunt.hcl + state.hcl only, wires up modules/develop
  workloads-dev/                  # a member account vended by modules/identity-center/accounts.tf
    account.hcl
    us-east-1/
      region.hcl
      develop/                    # same modules/develop, applied into this account instead
k8s/
  manifests/                      # raw upstream YAML, decoded+applied via kubernetes_manifest
  helm/                           # helm_release values files
policies/
  iam-policy-aws-load-balancer-controller.json
Makefile                          # make <layer> <command>, see below
mise.toml                         # pinned CLI tool versions (this repo + ../argo-k8s-helm)
.pre-commit-config.yaml           # fmt/validate/tflint/docs/conventional-commits, on every commit
.releaserc.yaml                   # semantic-release config (CHANGELOG.md, version tags)
CLAUDE.md                         # guidance for AI coding agents working in this repo
```

## Tooling

Versions are pinned in [`mise.toml`](mise.toml) — run `make setup` (`mise install`) once.

| Tool | Used for |
| --- | --- |
| `terraform` | the actual provisioning engine |
| `terragrunt` | layering, shared backend config, DRY inputs |
| `tflint` | `terraform_unused_declarations` and a handful of other rules, in pre-commit |
| `terraform-docs` | regenerates `modules/identity-center/README.md` and `modules/develop/README.md`'s inputs/outputs tables |
| `pre-commit` | runs all of the above + `conventional-pre-commit` on every commit |
| `awscli` | SSO login, `aws eks update-kubeconfig` |
| `helm` / `kubectl` / `kustomize` | ad-hoc cluster debugging and rendering — also used against the parked `../argo-k8s-helm` repo |

## Getting started

```bash
make setup                       # mise install
make login                       # aws sso login --profile lab-admin

make <layer> plan                # <layer> is 01-identity-center or eks-cluster
make <layer> apply
make run-all-plan                # plan every layer
make lint                        # pre-commit run --all-files
```

See [`CLAUDE.md`](CLAUDE.md) for the full command reference (`cmd`, `state-list`, `debug-plan`,
`force-provider-update`, etc.) and more detail on conventions (commit message format, where
`terraform-docs` output can and can't be hand-edited, why `pre-commit-terraform` is pinned).

## Identity model

Two AWS identities, used deliberately for different things:

- **`terraform`** — a static IAM user with `AdministratorAccess`. Used only by
  `01-identity-center`, because that stack *defines* the `lab-admin` role — running it under
  `lab-admin`'s own STS token would mean that role editing its own definition through itself.
- **`lab-admin`** — the `PlatformAdmin` SSO permission set `01-identity-center` creates. Used by
  every stack that *consumes* that identity instead of defining it (currently just `develop`).

`alice`/`bob` are the SSO users representing `payments-devs`/`search-devs` for the RBAC lab in
`develop/eks-access-lab.tf` — they get real IAM access only to `eks:DescribeCluster`/`ListClusters`;
their actual in-cluster permissions come entirely from Kubernetes RBAC RoleBindings, not IAM.
