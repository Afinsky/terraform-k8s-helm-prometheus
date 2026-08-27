# ArgoCD — the only Helm release Terraform still installs directly. Every
# other controller (LB Controller, ingress-nginx, external-dns,
# external-secrets) and every workload (photoapp, online-boutique) is
# deployed by ArgoCD from gitops/, not by Terraform. See gitops/README.md
# for the full layout.
#
# Terraform's involvement stops at two resources: this helm_release, and the
# single root Application below that points ArgoCD at gitops/clusters/develop.
# From that point on, nothing in gitops/ is ever created or modified by
# Terraform or by hand - it's reached exclusively by ArgoCD following
# root -> the ApplicationSets in clusters/develop/ -> platform/*/ and apps/*/.
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

locals {
  argocd_root_app_manifest = provider::kubernetes::manifest_decode(
    file("${path.module}/../../gitops/bootstrap/root.yaml")
  )
}

resource "kubernetes_manifest" "argocd_root_app" {
  manifest = local.argocd_root_app_manifest

  depends_on = [helm_release.argocd]
}
