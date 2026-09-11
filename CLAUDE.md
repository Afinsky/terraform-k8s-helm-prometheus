# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

Terraform-managed AWS EKS cluster ("homelab"-style dev environment). The workloads and add-ons
deployed onto it live in a **separate repository**, `argo-k8s-helm`
(github.com/Afinsky/argo-k8s-helm), reconciled by ArgoCD. Two repos, one clean handoff between
them:

- **this repo, `environments/develop/`** — Terraform. Owns anything that only AWS can create: VPC,
  EKS control plane, IAM/IRSA roles, ACM cert, ECR, the S3 state backend. Also installs ArgoCD
  itself (the one `helm_release` Terraform still runs) and applies exactly one more resource — a
  root ArgoCD `Application` pointing at the `argo-k8s-helm` repo (defined inline in `argocd.tf`,
  must stay in sync with `bootstrap/root.yaml` over there) — and then stops.
- **`argo-k8s-helm` repo (`gitops/` tree)** — ArgoCD. Owns every Helm release and every Kubernetes
  workload from that root `Application` down: cluster add-ons (LB Controller, ingress-nginx,
  external-dns, external-secrets) and apps (`photoapp`, `online-boutique`). Nothing there is ever
  touched by Terraform or by hand — see that repo's `gitops/README.md`. It is checked out locally
  at `/Users/aliaksei/WORK/argo-k8s-helm` as an additional working directory.

Single environment today: `environments/develop` / the `argo-k8s-helm` repo's `gitops/clusters/develop`.
State is remote (S3 backend), bootstrapped from a separate `00_bootstrap` config.

## Commands

All Terraform commands run from `environments/develop/` (the only active root module besides
the one-time bootstrap).

```bash
# Init (backend config is separate from the root module, see backend.tf + develop.conf)
terraform init -backend-config=develop.conf

# Standard plan/apply — var-file is required, profile comes from it
terraform plan  -var-file=develop.tfvars
terraform apply -var-file=develop.tfvars

# Formatting / linting (also run by pre-commit, see below)
terraform fmt -recursive
terraform validate
tflint --call-module-type=all --config=.tflint.hcl

# Regenerate README.md (terraform-docs) after adding/changing resources or variables
terraform-docs markdown table --config=.terraform-docs.yml --output-file README.md --output-mode inject environments/develop
```

The `argo-k8s-helm` repo has no Terraform commands at all — changes there are plain git
commits/PRs; ArgoCD picks them up on its own reconcile loop, nothing to run locally beyond
`kustomize build` / `helm template` to sanity-check a change renders before pushing.

Pre-commit hooks (`.pre-commit-config.yaml`) run `terraform_validate`, `terraform_fmt`,
`terraform_docs` (auto-regenerates each module's `README.md` between `BEGIN_TF_DOCS`/
`END_TF_DOCS` markers — don't hand-edit those sections), and a restricted `tflint` ruleset
(deprecated syntax, unused declarations, naming convention, pinned module sources, documented
variables/outputs, standard module structure). `tflint` is excluded on
`environments/develop/unused/` — that directory holds retired node-group configs
(`eks-al2.tf`, `eks-bottlerocket.tf`) kept for reference, not live code.

The one-time bootstrap (`environments/develop/00_bootstrap`) provisions the S3 state bucket
itself via `modules/backend`; it has its own local state and is not part of the normal
plan/apply loop — only touch it if changing how/where state is stored.

There is no test suite, CI config, or application build step in this repo — validation is
`terraform validate` + `tflint` + a working `plan` on the Terraform side, and `kustomize build` /
`helm template` on the gitops side.

## Architecture — Terraform (`environments/develop/`)

**`modules/backend`** — thin wrapper around `terraform-aws-modules/terraform-aws-s3-bucket`
that provisions the Terraform state bucket (versioned, encrypted, fully public-access-blocked).
Used only by `00_bootstrap`.

**`environments/develop`** — the real root module. Composition, in dependency order:

1. `vpc.tf` — `module.vpc` (`terraform-aws-modules/vpc/aws`): 2-AZ VPC with public/private/database
   subnets. Public subnets tagged `kubernetes.io/role/elb`, private tagged
   `kubernetes.io/role/internal-elb` — these tags are how AWS's Load Balancer Controller later
   picks subnets automatically.
2. `eks.tf` — `module.eks` (`terraform-aws-modules/eks/aws`): the cluster itself, one managed
   SPOT node group, three cluster addons (coredns, kube-proxy, vpc-cni — vpc-cni gets its own
   IRSA role). Also defines the `ebs_csi_driver` IRSA role (attachment lives in `eks.tf` but the
   addon itself is not currently declared under `addons {}` — check before assuming EBS storage
   works out of the box). EKS access (who can `kubectl`) is separate from IAM identity — see
   `local.eks_access_entries` / `eks_access_policy` in `locals.tf` and `access_entries` in
   `eks.tf`; today only the account root and one personal IAM user get admin, no viewer
   principals are configured.
3. `acm.tf` — wildcard ACM cert (`*.abotyan.click`) validated via the Route53 zone in `data.tf`.
   Its ARN is exposed as `output.acm_certificate_arn` for the one manual git paste described
   below — Terraform can't hand it to `gitops/` any other way.
4. `load-balancer-controller.tf` — IAM role/policy for the **AWS Load Balancer Controller** plus
   a `kubernetes_service_account_v1` carrying the IRSA annotation. The Helm release itself lives
   in `gitops/platform/aws-load-balancer-controller/` — Terraform's job ends at "the identity
   exists", ArgoCD's job is "the controller runs". IAM policy is a byte-for-byte copy of
   upstream's published policy (`policies/iam-policy-aws-load-balancer-controller.json`) —
   re-download from upstream, don't hand-edit, whenever the chart version bumps.
5. `external-dns.tf` — same shape as (4): IAM role/policy scoped to the single hosted zone
   (`local.zone_id`, not account-wide) plus a `kubernetes_namespace_v1` +
   `kubernetes_service_account_v1`. Helm release lives in `gitops/platform/external-dns/`.
6. `external-secrets.tf` — same shape again: IAM role/policy plus namespace + ServiceAccount.
   Helm release **and** the `ClusterSecretStore` custom resource both live in
   `gitops/platform/external-secrets/` now (the CR needs the chart's CRDs to exist first — see
   that Application's sync-wave comment).
7. `argocd.tf` — installs ArgoCD (`helm_release.argocd`, the only Helm release Terraform still
   runs directly) and applies the single root `Application`
   (`kubernetes_manifest.argocd_root_app`, defined inline in `argocd.tf` — keep it in sync with
   `bootstrap/root.yaml` in the `argo-k8s-helm` repo). This is the entire Terraform↔ArgoCD
   handoff — nothing else in that repo is ever referenced from here.
8. `ecr.tf` — one ECR repo per `local.project_name`.

**IRSA pattern**: every controller that needs AWS API access (vpc-cni, ebs-csi-driver, LB
Controller, external-dns, external-secrets) follows the same shape — a dedicated `aws_iam_role`
trusting `module.eks.oidc_provider_arn`, scoped via a `StringEquals` condition on
`{oidc_provider}:sub` to one specific `system:serviceaccount:<namespace>:<name>`, plus a
narrowly-scoped policy. For controllers whose Helm release lives in `gitops/` (everything except
vpc-cni/ebs-csi-driver, which are cluster addons), Terraform also creates the
`kubernetes_namespace_v1` + `kubernetes_service_account_v1` with the
`eks.amazonaws.com/role-arn` annotation baked in — the matching chart in `gitops/platform/<name>/`
deploys with `serviceAccount.create: false` and references that ServiceAccount by name. Follow
this pattern for any new controller requiring AWS permissions: IAM role/policy + ServiceAccount
in Terraform, Helm release in `gitops/`, never a `helm_release` resource for a new controller.

**Naming/tagging convention**: most resources key off `local.resource_name` /
`local.prefix` (built from `project_name` + `environment` + `region` in `locals.tf`) and
`local.common_tags` — reuse these locals rather than inventing new naming schemes.

**The one Terraform→git literal exception**: the ACM certificate ARN
(`gitops/platform/ingress-nginx/values-develop.yaml`). It's genuinely dynamic (assigned by AWS)
and there's no ServiceAccount-style bridge for a Service annotation, and no cert
auto-discovery for a plain Service-type NLB. Paste `terraform output -raw acm_certificate_arn`
into that file once after first apply; it's stable afterwards unless `acm.tf`'s certificate is
replaced. Every other value that used to be a Terraform `set`/`set_list` (`clusterName`, `region`,
`txtOwnerId`, `domainFilters`) is now a plain literal in the relevant `values-develop.yaml`,
because those are deterministic from `develop.tfvars`/`locals.tf`, not discovered at apply time —
see each file's header comment before assuming a new value needs the same manual-paste treatment
as the ACM ARN.

## Architecture — GitOps (`argo-k8s-helm` repo)

This tree lives in a **separate repo** (github.com/Afinsky/argo-k8s-helm), checked out locally at
`/Users/aliaksei/WORK/argo-k8s-helm`. All `repoURL`s in it point at `argo-k8s-helm.git`. Full
walkthrough, rationale, and how this scales to more clusters/environments lives in that repo's
`gitops/README.md`. Short version (paths are relative to that repo):

```
gitops/bootstrap/root.yaml           the one Application Terraform applies (argocd.tf)
gitops/projects/{platform,apps}.yaml AppProject RBAC boundary between add-ons and workloads
gitops/clusters/develop/             two ApplicationSets fanning out platform/* and apps/*
gitops/platform/<name>/              one add-on: generator.yaml + values (or, for the one
                                      exception that needs more, a hand-written application.yaml)
gitops/apps/<name>/                  one Application per workload (Kustomize base + overlays)
```

Adding a new app is "add a directory, commit". Adding a new platform add-on is the same *unless*
it needs more than "chart + values" — see `gitops/README.md` for both paths and why
`platform/external-secrets/` is the one hand-authored exception (it needs a third source for its
`ClusterSecretStore`, which `platform-appset.yaml`'s generic per-component template can't
express). Either way: never register something with Argo by hand, and never a new `helm_release`
in Terraform.

Cross-controller ordering (LB Controller before ingress-nginx before external-dns) is **not**
enforced by ArgoCD `sync-wave` at the Application level — ApplicationSet-generated Applications
are independent top-level objects, not children of one parent sync, so that annotation wouldn't
be evaluated. Ordering is retry/self-heal instead (`syncPolicy.retry` with backoff on each
Application): a dependent resource create can transiently fail until its dependency is up, and
clears on the next retry. `sync-wave` **is** used correctly within `platform/external-secrets/`'s
own Application, where the chart and the `ClusterSecretStore` CR are two sources of the *same*
sync operation.

## Known gaps / in-flight state

- `terraform apply` has not been run against this configuration at all — the reasoning behind it
  is documented throughout, but nothing has been verified live yet, including the ArgoCD
  bootstrap itself.
- `gitops/platform/ingress-nginx/values-develop.yaml`'s ACM cert ARN is a placeholder
  (`REPLACE_AFTER_FIRST_APPLY`) until someone pastes the real value in — see the exception noted
  above. ingress-nginx (and everything behind it: external-dns, the apps' Ingresses) won't
  actually serve HTTPS correctly until that's done.
- ArgoCD itself has no ingress/TLS/SSO configured yet (`argocd.tf`'s header comment) — reachable
  only via `kubectl port-forward` until that's addressed.
- No Prometheus/Grafana/Loki stack exists yet despite the repo name — that's still on the
  informal to-do list, not yet implemented. Once added, it belongs in `gitops/platform/`, not as
  a new `helm_release` in Terraform.

## Agent skills

### Issue tracker

Issues are tracked in GitHub Issues (github.com/Afinsky/terraform-k8s-helm-prometheus), using the
`gh` CLI. See `docs/agents/issue-tracker.md`.

### Domain docs

Single-context layout — `CONTEXT.md` + `docs/adr/` at the repo root, created lazily by
`/domain-modeling`. See `docs/agents/domain.md`.
