# PLAT-101 lab, Phase 3 (Kubernetes-side half): namespaces standing in for
# "environments", and the RBAC RoleBindings that pair with the SSO access
# entries created in modules/eks-cluster/eks-access-lab.tf (the AWS-IAM half -
# those access entries are created as part of that module's own `module.eks`
# call, so they stayed there rather than moving here with everything else).
#
# Same decode-and-apply pattern as app.tf/online-boutique.tf: raw YAML lives
# in k8s/manifests/, don't hand-write kubernetes_manifest blocks for it.
# Split into two resources (rather than one) so the depends_on below can
# guarantee the namespaces exist before Kubernetes tries to create
# RoleBindings inside them - kubernetes_manifest gives no ordering between
# count instances of the same resource on its own.
locals {
  eks_access_lab_namespaces_raw_yaml = file("${var.repo_root}/k8s/manifests/eks-access-lab-namespaces.yaml")
  eks_access_lab_namespaces          = provider::kubernetes::manifest_decode_multi(local.eks_access_lab_namespaces_raw_yaml)

  eks_access_lab_rolebindings_raw_yaml = file("${var.repo_root}/k8s/manifests/eks-access-lab-rolebindings.yaml")
  eks_access_lab_rolebindings          = provider::kubernetes::manifest_decode_multi(local.eks_access_lab_rolebindings_raw_yaml)
}

resource "kubernetes_manifest" "eks_access_lab_namespaces" {
  count    = length(local.eks_access_lab_namespaces)
  manifest = local.eks_access_lab_namespaces[count.index]
}

resource "kubernetes_manifest" "eks_access_lab_rolebindings" {
  count    = length(local.eks_access_lab_rolebindings)
  manifest = local.eks_access_lab_rolebindings[count.index]

  depends_on = [kubernetes_manifest.eks_access_lab_namespaces]
}
