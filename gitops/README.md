# gitops/

Everything ArgoCD reconciles onto the `develop` cluster. Terraform (in
`environments/develop/`) creates exactly one thing here: the root
`Application` in [`bootstrap/root.yaml`](bootstrap/root.yaml), applied once
via `kubernetes_manifest` in `argocd.tf`. Nothing else in this tree is ever
touched by Terraform or by hand — every other resource is reached by
following `root` → the two `ApplicationSet`s in `clusters/develop/` →
whatever `platform/*/` and `apps/*/` contain.

See the design rationale and full walkthrough (why this split, how it
scales to more clusters/environments, what stays in Terraform and why) in
the project's GitOps Blueprint artifact linked from the PR that introduced
this directory.

## Layout

```
bootstrap/            the one manually-applied Application (Terraform's job)
clusters/develop/      ApplicationSets that fan out platform/ and apps/ onto this cluster
platform/<name>/       one Argo Application per cluster add-on (upstream Helm chart + values)
apps/<name>/           one Argo Application per workload (Kustomize base + overlays)
projects/               AppProject definitions — the RBAC boundary between platform/ and apps/
```

## Adding a new platform add-on

Most add-ons: no Application to write at all.

1. Create `platform/<name>/generator.yaml` (chart repo/name/version +
   destination namespace — copy `platform/external-dns/generator.yaml`'s
   shape) and `platform/<name>/values-base.yaml`.
2. If it needs AWS permissions: add the IAM role + `kubernetes_service_account_v1`
   in Terraform first (same IRSA pattern as every other controller in
   `environments/develop/`), then reference that ServiceAccount by name in
   `values-base.yaml` with `serviceAccount.create: false`.
3. Commit. `clusters/develop/platform-appset.yaml`'s `files` generator picks
   up the new `generator.yaml` on its next reconcile and creates the
   Application — nothing else to register.

Exception: if the add-on needs more than "chart + values" (a CRD instance
alongside it, like `platform/external-secrets/`'s `ClusterSecretStore`),
don't add a `generator.yaml` — hand-write `platform/<name>/application.yaml`
instead and add one more source entry to `bootstrap/root.yaml` pointing at
it with `directory.include: "application.yaml"`. See
`platform/external-secrets/application.yaml`'s header comment for why that
one component needs this.

## Adding a new application

1. Create `apps/<name>/base/` (Kustomize resources) and
   `apps/<name>/overlays/develop/kustomization.yaml`.
2. Commit. `apps-develop` ApplicationSet picks it up the same way.

## What never goes in this tree

Anything that only AWS can create (VPC, EKS control plane, IAM roles, ACM
certs, ECR repos, the S3 state bucket) — that stays in
`environments/develop/*.tf`. If a resource needs an AWS-issued ARN, the
bridge is a Terraform-created `ServiceAccount`, not a value injected into
this repo.
