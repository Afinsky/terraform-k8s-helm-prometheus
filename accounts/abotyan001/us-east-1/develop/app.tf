locals {
  raw_yaml = file("${var.repo_root}/k8s/manifests/app.yaml")

  # kubernetes_manifest refuses namespaced resources whose manifest has no
  # explicit metadata.namespace (it does not fall back to "default" the way
  # kubectl does). The manifests in app.yaml omit it, so inject "default"
  # wherever it is missing rather than hand-editing every doc.
  k8s_manifests = [
    for m in provider::kubernetes::manifest_decode_multi(local.raw_yaml) :
    merge(m, {
      metadata = merge(m.metadata, {
        namespace = try(m.metadata.namespace, "default")
      })
    })
  ]
}

resource "kubernetes_manifest" "app" {
  count    = length(local.k8s_manifests)
  manifest = local.k8s_manifests[count.index]

  # app.yaml's Ingress uses ingressClassName "nginx" - wait for the
  # controller that reconciles it (see ingress-nginx.tf) to exist, same
  # depends_on reasoning used by the other resources in this repo. app.yaml
  # also now has an ExternalSecret (photoapp-db-credentials) - it needs the
  # ExternalSecret CRD and the ClusterSecretStore it references to exist
  # first (see external-secrets.tf).
  depends_on = [
    module.eks,
    helm_release.ingress_nginx,
    helm_release.external_secrets,
    kubernetes_manifest.external_secrets_cluster_store,
  ]
}
