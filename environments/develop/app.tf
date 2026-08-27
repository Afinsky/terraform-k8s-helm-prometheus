# locals {
#   raw_yaml      = file("${path.module}/../../k8s/manifests/app.yaml")
#   k8s_manifests = provider::kubernetes::manifest_decode_multi(local.raw_yaml)
# }
#
# resource "kubernetes_manifest" "app" {
#   count    = length(local.k8s_manifests)
#   manifest = local.k8s_manifests[count.index]
#
#   # app.yaml's Ingress uses ingressClassName "nginx" - wait for the
#   # controller that reconciles it (see ingress-nginx.tf) to exist, same
#   # depends_on reasoning used by the other resources in this repo. app.yaml
#   # also now has an ExternalSecret (photoapp-db-credentials) - it needs the
#   # ExternalSecret CRD and the ClusterSecretStore it references to exist
#   # first (see external-secrets.tf).
#   depends_on = [
#     module.eks,
#     helm_release.ingress_nginx,
#     helm_release.external_secrets,
#     kubernetes_manifest.external_secrets_cluster_store,
#   ]
# }
