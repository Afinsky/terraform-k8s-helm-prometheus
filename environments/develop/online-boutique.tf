# # Online Boutique (GoogleCloudPlatform/microservices-demo) - an 11-service
# # demo app (frontend, cart, checkout, payment, shipping, product catalog,
# # currency, recommendation, ad, email, and a redis-cart cache), pulled in as
# # a multi-container app to practice Prometheus/Grafana monitoring setup
# # against a real service-to-service topology, rather than the single-container
# # app.yaml. Same decode-and-apply pattern as app.tf: raw upstream YAML lives
# # in k8s/manifests/online-boutique.yaml (see that file's header comment for
# # what was changed from the upstream release), don't hand-write
# # kubernetes_manifest blocks for it.
# locals {
#   online_boutique_raw_yaml = file("${path.module}/../../k8s/manifests/online-boutique.yaml")
#   online_boutique_manifests = provider::kubernetes::manifest_decode_multi(
#     local.online_boutique_raw_yaml
#   )
# }
#
# resource "kubernetes_manifest" "online_boutique" {
#   count    = length(local.online_boutique_manifests)
#   manifest = local.online_boutique_manifests[count.index]
#
#   # Same reasoning as kubernetes_manifest.app in app.tf: the Ingress here
#   # uses ingressClassName "nginx", so ingress-nginx's controller must exist
#   # first.
#   depends_on = [
#     module.eks,
#     helm_release.ingress_nginx,
#   ]
# }
