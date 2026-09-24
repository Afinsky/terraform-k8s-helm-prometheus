# terraform-k8s-helm-prometheus

A personal AWS/EKS homelab, provisioned with Terraform via Terragrunt: IAM Identity Center
SSO, IRSA, and Terragrunt layering, applied for real against a live AWS Organization —
not a course exercise or a throwaway sandbox.

One AWS Organization rooted in `abotyan001`, member accounts (currently `workloads-dev`)
each getting their own `eks-cluster` + `eks-workloads` layer pair, one region (`us-east-1`).
Everything on the cluster (VPC, EKS, ingress-nginx, external-dns, external-secrets, sample
apps) is applied directly from this repo — there is no GitOps/ArgoCD reconciliation involved
right now (see [GitOps status](#gitops-status-parked) below).

## Architecture

```
AWS Organization, region: us-east-1
│
│  every layer is a unit generated from its account's terragrunt.stack.hcl
│  (templates in units/)
│
├─ abotyan001 (management account, 417886991962)
│  └─ identity-center      AWS Organization + IAM Identity Center (SSO)
│                           groups/users/permission sets. Applies as the
│                           static "terraform" IAM user. No workload infra
│                           runs in the management account.
│
└─ workloads-dev (member account, vended by identity-center)
   ├─ eks-cluster          VPC, EKS control plane/node groups, ACM - pure AWS,
   │                        no Kubernetes/Helm provider. Applies as
   │                        "workloads-dev.devops-admin".
   │
   └─ eks-workloads        IRSA controllers, ingress-nginx, cluster-admin RBAC,
                            sample apps - depends on eks-cluster's outputs.
                            Applies as "workloads-dev.devops-admin". Destroyed
                            *before* eks-cluster (see "Destroy order" below).
```

Layers are applied in order: `identity-center` first creates the SSO permission sets
everything else runs as, then `eks-cluster`, then `eks-workloads` (which reads `eks-cluster`'s
outputs via a Terragrunt `dependency` block - see [`modules/eks-cluster`'s README](modules/eks-cluster/README.md)
for why they're two layers instead of one).

### Terragrunt layering

- [`root.hcl`](root.hcl) (repo root, included by every `terragrunt.hcl`) consolidates
  [`global.hcl`](global.hcl) (project name, common tags), `accounts/abotyan001/account.hcl`
  (account ID/alias) and `accounts/abotyan001/us-east-1/region.hcl` into `inputs` for every layer.
- It also configures the shared S3 state backend (`dev-me-terraform-state`). The bucket is
  **never a terraform resource anywhere** — Terragrunt creates it itself (versioned,
  AES256-encrypted, public access blocked) the first time it's missing, via
  `--backend-bootstrap` baked into every `Makefile` command. Each layer's own state key comes
  from a sibling `state.hcl`, so migrating to Terragrunt didn't require moving any state.
- There's no `generate "provider"` block: `eks-workloads`'s kubernetes/helm providers need
  `eks-cluster`'s outputs (passed as plain inputs across the Terragrunt `dependency` boundary,
  not a `module.eks` reference), which Terragrunt can't template statically, so `provider.tf` is a
  hand-written, committed file (in each module — see below).
- Every layer is a thin wrapper: each `terragrunt.hcl` has no Terraform of its own, just a
  `terraform { source = "${get_repo_root()}/modules/<name>" }` block plus `inputs`.
- Every layer is a [Terragrunt stack](https://terragrunt.gruntwork.io/docs/features/stacks)
  unit: its `terragrunt.hcl` exists once, as a template under [`units/`](units), and each
  account instantiates its layers from a single `accounts/<alias>/us-east-1/terragrunt.stack.hcl`
  holding only what differs per account (SSO profile, environment, VPC ranges).
  `terragrunt stack generate` expands it into a gitignored `.terragrunt-stack/` next to it;
  every `make` target regenerates every account's stack before running (`make stacks`).
  `modules/eks-cluster` and `modules/eks-workloads` are reused across workload accounts this
  way; `modules/identity-center` defines the Organization itself, so its `identity-center`
  unit is instantiated exactly once, by the management account — a stack unit purely so every
  layer is shaped the same way.
- `eks-cluster` and `eks-workloads` are split into two layers (not one) specifically so
  `terraform destroy` is safe: destroying `eks-workloads` first, while the cluster and its
  controllers are still up, lets the AWS Load Balancer Controller actually deprovision any
  ALB/NLB it created before `eks-cluster`'s VPC/subnets get destroyed. One state for both risked
  an orphaned LB (and its ENIs) blocking subnet deletion. See `make destroy-safe` below.

### `identity-center`

Creates the AWS Organization and IAM Identity Center: three users (`aliaksei`, `alice`, `bob`),
three groups, and the permission sets/account assignments that turn into SSO roles:

- **`platform-admin`** — `AdministratorAccess`, assigned to `platform-admins`, scoped to just the
  management account (`abotyan001-root`).
- **`devops-admin`** — `AdministratorAccess` on every account in the Organization, assigned to
  `devops-admins`. Becomes the `<account-name>.devops-admin` SSO profile (e.g.
  `abotyan001-root.devops-admin`, `workloads-dev.devops-admin` — see `make aws-sso-configure-populate`,
  which generates these in `~/.aws/config` via `aws-sso-util`) that `eks-cluster`/`eks-workloads`
  apply as.
- **`developer`** — minimal IAM (just enough to find the cluster), assigned to `developers`, on
  `workloads-dev` and the management account. Real Kubernetes access comes later, from EKS access
  entries + RBAC defined in `eks-cluster`/`eks-workloads` — not from IAM.

Also creates **ECR** (`ecr.tf`) — one repository, in the management account only (not
per-account like `eks-cluster`/`eks-workloads`).

Always applies as the static `terraform` IAM user, never `devops-admin`: this stack defines that
role, so running it under its own not-yet-revocable STS token risks a self-lockout (see the
comment in `provider.tf`).

### `eks-cluster`

Pure AWS - no Kubernetes/Helm provider anywhere in this module:

- **VPC** (`terraform-aws-modules/vpc/aws`) — single NAT gateway, flow logs optional.
- **EKS** (`terraform-aws-modules/eks/aws`) — one SPOT-capacity managed node group,
  access-entries-only auth (no `aws-auth` ConfigMap). Also creates the SSO-role access entries
  (`eks-access.tf`): `devops-admin` gets cluster-admin (plus a native RBAC `ClusterRoleBinding`
  in `eks-workloads`), `developer` gets cluster-wide read-only, `platform-admin` gets cluster-admin
  where it's assigned (management account only).
- **ACM** + **Route53** — one wildcard cert, DNS validation (cross-account - see
  [`modules/identity-center`'s `dns.tf`](modules/identity-center/dns.tf)).

Applies as `<account-name>.devops-admin` — a consumer of the identity `identity-center`
defines, with no self-reference risk.

### `eks-workloads`

Everything that talks to the cluster's own Kubernetes API - depends on `eks-cluster`'s outputs
via a Terragrunt `dependency` block, applied after it and **destroyed before it**:

- **IRSA controllers** — `aws-load-balancer-controller`, `external-dns`, `external-secrets`.
  Each gets a dedicated IAM role trusting only its own ServiceAccount via OIDC, with a policy
  scoped as narrowly as the controller allows (e.g. `external-secrets` only gets
  `GetSecretValue` on a naming-prefix, not account-wide `ListSecrets`; `external-dns`'s role
  only gets `sts:AssumeRole` on the cross-account `dns-zone-writer` role, no direct Route53
  access). New controllers should follow the same shape rather than reuse or widen an existing
  role.
- **ingress-nginx** — fronted by the load balancer controller.
- **RBAC** (`rbac.tf`) — a `devops-admins` `ClusterRoleBinding` to `cluster-admin`, native-RBAC
  admin for the real day-to-day admin group (paired with the AWS access-policy admin association
  `eks-cluster` also grants that group — see below).
- **Sample apps** — a small photo app (`app.tf`) and Online Boutique
  (`online-boutique.tf`, [GoogleCloudPlatform/microservices-demo](https://github.com/GoogleCloudPlatform/microservices-demo)),
  applied as `kubernetes_manifest` from raw upstream YAML in `k8s/manifests/` (namespace
  injected in Terraform — `kubernetes_manifest` needs it explicit, unlike `kubectl`). These
  exist to practice a real multi-service topology, which is also where the "prometheus" in this
  repo's name comes from — no Prometheus/Grafana stack is actually deployed yet.

Also applies as `<account-name>.devops-admin`.

### Destroy order

`eks-workloads` before `eks-cluster` — `make run-all-destroy`/`terragrunt run --all destroy`
already get this right automatically (reverse of the `dependency` graph), but a slow ALB/NLB
deprovision can still outlast a `helm_release`'s destroy timeout (bumped to 600s, still finite)
and get orphaned, blocking `eks-cluster`'s VPC/subnet destroy. `make destroy-safe` additionally
polls `aws elbv2` between the two destroys instead of trusting the timeout alone.

## GitOps status: parked

A sibling repo, [`argo-k8s-helm`](https://github.com/Afinsky/argo-k8s-helm) (checked out at
`../argo-k8s-helm`), contains an ArgoCD-based GitOps setup for these same add-ons and apps.
**It's a parked experiment, not in use.** This repo's Terraform is the sole source of truth for
the live cluster; nothing here references the gitops repo.

## Repository layout

```
root.hcl                          # Terragrunt root config: backend, version constraints, inputs
global.hcl                        # project_name, common_tags
modules/
  identity-center/                # all of layer 1's Terraform — see above
  eks-cluster/                    # all of layer 2's Terraform — see above
    unused/                       # archived alternative node-group configs (not compiled)
  eks-workloads/                  # all of layer 3's Terraform — see above
units/                            # Terragrunt unit templates, instantiated per account by a stack file
  identity-center/                # layer 1 — terragrunt.hcl + state.hcl + lock file, wires up modules/identity-center
  eks-cluster/                    # layer 2 — same, wires up modules/eks-cluster
  eks-workloads/                  # layer 3 — same, depends on the eks-cluster unit generated next to it
accounts/
  abotyan001/                     # the management account
    account.hcl                   # aws_account_alias, aws_account_id
    us-east-1/
      region.hcl                  # aws_region
      terragrunt.stack.hcl        # layer 1 only: units/identity-center plus its values
      .terragrunt-stack/          # generated from terragrunt.stack.hcl, gitignored
  workloads-dev/                  # a member account vended by modules/identity-center/accounts.tf
    account.hcl                   # + its own state bucket/profile/role
    us-east-1/
      region.hcl
      terragrunt.stack.hcl        # layers 2+3 for this account: units/eks-* plus this account's values
      .terragrunt-stack/          # generated from terragrunt.stack.hcl, gitignored
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
| `terraform-docs` | regenerates each module's `README.md` inputs/outputs tables (`identity-center`, `eks-cluster`, `eks-workloads`) |
| `pre-commit` | runs all of the above + `conventional-pre-commit` on every commit |
| `awscli` | `aws sts`/`aws eks update-kubeconfig`, general AWS CLI use |
| `aws-sso-util` | SSO login (`make login`) and generating `~/.aws/config` profiles (`make aws-sso-configure-populate`) |
| `helm` / `kubectl` / `kustomize` | ad-hoc cluster debugging and rendering — also used against the parked `../argo-k8s-helm` repo |

## Getting started

```bash
make setup                       # mise install
make login                       # aws-sso-util login (opens a browser SSO login)
make aws-sso-configure-populate      # generate ~/.aws/config profiles for every account/permission set

make identity-center plan     # management account (ACCOUNT defaults to abotyan001)
make ACCOUNT=workloads-dev eks-cluster plan    # eks-* need a workload account (see make accounts)
make ACCOUNT=workloads-dev eks-workloads apply # apply eks-cluster before eks-workloads
make ACCOUNT=workloads-dev run-all-plan        # plan every layer of one account
make ACCOUNT=workloads-dev run-all-apply       # dependency-ordered: eks-cluster before eks-workloads
make destroy-safe                # destroy eks-workloads, wait for its LBs to clear, then eks-cluster
make lint                        # pre-commit run --all-files
```

### Adding a workload account

1. Vend it from `modules/identity-center/accounts.tf` (`make identity-center apply`), then
   `make aws-sso-configure-populate` for its `<name>.devops-admin` SSO profile.
2. Copy `accounts/workloads-dev/` to `accounts/<alias>/` and edit:
   - `account.hcl` — alias, account ID, and **its own** `state_bucket`/`state_profile`/
     `state_role_arn`. Without them `root.hcl` falls back to the management account's bucket,
     where every account's `eks-cluster` key would collide.
   - `us-east-1/terragrunt.stack.hcl` — `profile`, `environment`, and a VPC range that doesn't
     overlap any other account's.
3. `make ACCOUNT=<alias> eks-cluster apply`, then `make ACCOUNT=<alias> eks-workloads bootstrap-crds`
   and `make ACCOUNT=<alias> eks-workloads apply` (see the `bootstrap-crds` target's comment for why).
4. Add its units to `.github/workflows/plan.yml`'s matrix (`chain: true`, its `account_id`).

See [`CLAUDE.md`](CLAUDE.md) for the full command reference (`cmd`, `state-list`, `debug-plan`,
`force-provider-update`, etc.) and more detail on conventions (commit message format, where
`terraform-docs` output can and can't be hand-edited, why `pre-commit-terraform` is pinned).

## Identity model

Two AWS identities, used deliberately for different things:

- **`terraform`** — a static IAM user with `AdministratorAccess`. Used only by
  `identity-center`, because that stack *defines* the `devops-admin` role — running it under
  `devops-admin`'s own STS token would mean that role editing its own definition through itself.
- **`devops-admin`** — the SSO permission set `identity-center` creates (profile named
  `<account-name>.devops-admin` per account, generated into `~/.aws/config` by
  `make aws-sso-configure-populate` — see `~/.aws/config`). Used by every stack that
  *consumes* that identity instead of defining it (`eks-cluster` and `eks-workloads`).

`alice` is the SSO user for the `developer` role (member of `developers`, assigned the
`developer` permission set, `eks-cluster/eks-access.tf`) — real IAM access is limited to
`eks:DescribeCluster`/`ListClusters`, but her EKS access entry's `AmazonEKSViewPolicy`
association gives her cluster-wide read-only in Kubernetes itself.
