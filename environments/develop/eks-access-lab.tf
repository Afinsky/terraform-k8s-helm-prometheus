# PLAT-101 lab, Phase 3: EKS access via IAM Identity Center SSO roles +
# Kubernetes RBAC, instead of static IAM users. Namespaces payments-dev /
# payments-prod / search-dev stand in for separate environments per the lab
# brief. This reuses the existing dev cluster instead of a dedicated one -
# same account/region, and the access-entry/RBAC pattern doesn't need its
# own infrastructure to be meaningful.
#
# Identity side (groups/users/permission sets) lives in a separate Terraform
# stack: eks-access-lab/01-identity. This file only consumes what it
# creates, by looking up the resulting IAM roles - no remote state, no
# hardcoded ARNs.

locals {
  # SSO role names carry a random suffix that changes if the permission
  # set's account assignment is ever recreated - look roles up by name
  # regex instead of hardcoding the ARN.
  sso_role_patterns = {
    platform_admin = "AWSReservedSSO_PlatformAdmin_.*"
    payments       = "AWSReservedSSO_EKSDev-Payments_.*"
    search         = "AWSReservedSSO_EKSDev-Search_.*"
  }
}

data "aws_iam_roles" "sso" {
  for_each    = local.sso_role_patterns
  name_regex  = each.value
  path_prefix = "/aws-reserved/sso.amazonaws.com/"
}

locals {
  # one() errors out if more than one role matches - better to fail loudly
  # at plan time than silently grant access via the wrong role.
  sso_role_arn = { for k, v in data.aws_iam_roles.sso : k => one(v.arns) }

  lab_access_entries = {
    "eks-access-lab-platform-admin" = {
      kubernetes_groups = []
      principal_arn     = local.sso_role_arn.platform_admin
      policy_associations = {
        admin = {
          policy_arn = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
          access_scope = {
            type = "cluster"
          }
        }
      }
    }
    # alice: edit in payments-dev via an AWS access policy, plus the
    # payments-devs kubernetes_groups membership that the view RoleBinding
    # below (in payments-prod) targets.
    "eks-access-lab-payments" = {
      kubernetes_groups = ["payments-devs"]
      principal_arn     = local.sso_role_arn.payments
      policy_associations = {
        edit = {
          policy_arn = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSEditPolicy"
          access_scope = {
            type       = "namespace"
            namespaces = ["payments-dev"]
          }
        }
      }
    }
    # bob: no access policy at all here - every right he has in search-dev
    # comes from the RoleBinding below, purely via RBAC.
    "eks-access-lab-search" = {
      kubernetes_groups = ["search-devs"]
      principal_arn     = local.sso_role_arn.search
    }
  }
}

# --- Namespaces standing in for "environments" ---
resource "kubernetes_namespace_v1" "payments_dev" {
  metadata {
    name = "payments-dev"
  }
  depends_on = [module.eks]
}

resource "kubernetes_namespace_v1" "payments_prod" {
  metadata {
    name = "payments-prod"
  }
  depends_on = [module.eks]
}

resource "kubernetes_namespace_v1" "search_dev" {
  metadata {
    name = "search-dev"
  }
  depends_on = [module.eks]
}

# alice: view only in payments-prod, no Secrets - the built-in "view"
# ClusterRole excludes them, unlike "edit" (which is why payments-dev and
# payments-prod use different access levels).
resource "kubernetes_role_binding_v1" "payments_devs_view_prod" {
  metadata {
    name      = "payments-devs-view"
    namespace = kubernetes_namespace_v1.payments_prod.metadata[0].name
  }
  subject {
    kind      = "Group"
    name      = "payments-devs"
    api_group = "rbac.authorization.k8s.io"
  }
  role_ref {
    kind      = "ClusterRole"
    name      = "view"
    api_group = "rbac.authorization.k8s.io"
  }
}

# bob: full edit rights in search-dev.
resource "kubernetes_role_binding_v1" "search_devs_edit" {
  metadata {
    name      = "search-devs-edit"
    namespace = kubernetes_namespace_v1.search_dev.metadata[0].name
  }
  subject {
    kind      = "Group"
    name      = "search-devs"
    api_group = "rbac.authorization.k8s.io"
  }
  role_ref {
    kind      = "ClusterRole"
    name      = "edit"
    api_group = "rbac.authorization.k8s.io"
  }
}
