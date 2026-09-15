# The real day-to-day admin group (Identity Center's "devops-admins" - see
# modules/identity-center/sso.tf and permission_sets.tf) gets genuine
# Kubernetes RBAC cluster-admin here, paired with the "devops-admins"
# kubernetes_groups entry on its access entry in modules/eks-cluster/eks.tf.
# That access entry's AWS access-policy association (AmazonEKSClusterAdminPolicy)
# already grants equivalent permissions through EKS's own authorization
# layer - this ClusterRoleBinding is the native-RBAC route to the same
# result, so `kubectl` and anything that only understands RBAC (not EKS
# access policies) sees this group as admin too.
resource "kubernetes_cluster_role_binding_v1" "devops_admins" {
  metadata {
    name = "devops-admins-cluster-admin"
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = "cluster-admin"
  }

  subject {
    kind      = "Group"
    name      = "devops-admins"
    api_group = "rbac.authorization.k8s.io"
  }
}
