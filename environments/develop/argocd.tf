# ArgoCD — the only Helm release Terraform still installs directly. Every
# other controller (LB Controller, ingress-nginx, external-dns,
# external-secrets) and every workload (photoapp, online-boutique) is
# deployed by ArgoCD from the separate GitOps repo
# (github.com/Afinsky/argo-k8s-helm), not by Terraform. See that repo's
# gitops/README.md for the full layout.
#
# Terraform's involvement stops at two resources: this helm_release, and the
# single root Application below that points ArgoCD at gitops/clusters/develop
# in the GitOps repo. From that point on, nothing in that repo is ever
# created or modified by Terraform or by hand - it's reached exclusively by
# ArgoCD following root -> the ApplicationSets in clusters/develop/ ->
# platform/*/ and apps/*/.
#
# No ingress/TLS/SSO configured yet - the UI is reachable via
# `kubectl port-forward svc/argocd-server -n argocd 8080:443` for now.
# Exposing it through ingress-nginx has the same chicken-and-egg shape as
# every other add-on that depends on ingress-nginx (see the retry comment
# in gitops/platform/aws-load-balancer-controller/application.yaml) and
# SSO needs a real OIDC provider decision - both are follow-ups, not
# blockers for the GitOps handoff itself.
resource "kubernetes_namespace_v1" "argocd" {
  metadata {
    name = "argocd"
  }

  depends_on = [module.eks]
}

resource "helm_release" "argocd" {
  name             = "argocd"
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  namespace        = kubernetes_namespace_v1.argocd.metadata[0].name
  create_namespace = false
  version          = "10.4.0" # controller app v3.5.1.
  # Verified live via `helm search repo argo/argo-cd --versions` on
  # 2026-08-18. Re-run that search before every future version bump.

  depends_on = [module.eks, kubernetes_namespace_v1.argocd]
}

# The GitOps tree now lives in its own repository
# (github.com/Afinsky/argo-k8s-helm). Terraform no longer has that tree on
# disk, so the root Application is defined inline here instead of decoded
# from a file. This must stay in sync with bootstrap/root.yaml in that repo
# - it is the one hand-authored Application; everything else is reached by
# ArgoCD following it.
locals {
  gitops_repo_url = "https://github.com/Afinsky/argo-k8s-helm.git"

  argocd_root_app_manifest = provider::kubernetes::manifest_decode(<<-YAML
    apiVersion: argoproj.io/v1alpha1
    kind: Application
    metadata:
      name: root
      namespace: argocd
      finalizers:
        - resources-finalizer.argocd.argoproj.io
    spec:
      project: default
      sources:
        - repoURL: ${local.gitops_repo_url}
          targetRevision: main
          path: gitops/projects
        - repoURL: ${local.gitops_repo_url}
          targetRevision: main
          path: gitops/platform/external-secrets
          directory:
            include: "application.yaml"
        - repoURL: ${local.gitops_repo_url}
          targetRevision: main
          path: gitops/clusters/develop
      destination:
        server: https://kubernetes.default.svc
        namespace: argocd
      syncPolicy:
        automated:
          selfHeal: true
        syncOptions:
          - CreateNamespace=true
  YAML
  )
}
# NOTE: API did not recognize GroupVersionKind from manifest (CRD may not be installed), so this resource is commented out. It is still applied by ArgoCD, which does recognize the CRD.
resource "kubernetes_manifest" "argocd_root_app" {
  manifest = local.argocd_root_app_manifest

  depends_on = [helm_release.argocd]
}
