# PLAT-101 lab, Phase 3: EKS access via IAM Identity Center SSO roles +
# Kubernetes RBAC, instead of static IAM users. Namespaces payments-dev /
# payments-prod / search-dev stand in for separate environments per the lab
# brief. This reuses the existing dev cluster instead of a dedicated one -
# same account/region, and the access-entry/RBAC pattern doesn't need its
# own infrastructure to be meaningful.
#
# Identity side (groups/users/permission sets) lives in a separate Terraform
# stack: eks-access-lab/01-identity-center. This file only consumes what it
# creates, by looking up the resulting IAM roles - no remote state, no
# hardcoded ARNs.

locals {
  # SSO role names carry a random suffix that changes if the permission
  # set's account assignment is ever recreated - look roles up by name
  # regex instead of hardcoding the ARN. Permission set names come from
  # 01-identity-center/permission_sets.tf: platform-admin/devops-admin/
  # developer (there's no more per-team Payments/Search split there - payments
  # and search below just keep the prior slots so this lab's namespace/RBAC
  # shape below didn't need touching too).
  sso_role_patterns = {
    platform_admin = "AWSReservedSSO_platform-admin_.*"
    payments       = "AWSReservedSSO_devops-admin_.*"
    search         = "AWSReservedSSO_developer_.*"
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

# Namespaces standing in for "environments", and the RBAC RoleBindings that
# pair with the SSO access entries above. Same decode-and-apply pattern as
# app.tf/online-boutique.tf: raw YAML lives in k8s/manifests/, don't
# hand-write kubernetes_manifest blocks for it. Split into two files/
# resources (rather than one) so the depends_on below can guarantee the
# namespaces exist before Kubernetes tries to create RoleBindings inside
# them - kubernetes_manifest gives no ordering between count instances of
# the same resource on its own.
locals {
  eks_access_lab_namespaces_raw_yaml = file("${var.repo_root}/k8s/manifests/eks-access-lab-namespaces.yaml")
  eks_access_lab_namespaces          = provider::kubernetes::manifest_decode_multi(local.eks_access_lab_namespaces_raw_yaml)

  eks_access_lab_rolebindings_raw_yaml = file("${var.repo_root}/k8s/manifests/eks-access-lab-rolebindings.yaml")
  eks_access_lab_rolebindings          = provider::kubernetes::manifest_decode_multi(local.eks_access_lab_rolebindings_raw_yaml)
}

resource "kubernetes_manifest" "eks_access_lab_namespaces" {
  count    = length(local.eks_access_lab_namespaces)
  manifest = local.eks_access_lab_namespaces[count.index]

  depends_on = [module.eks]
}

resource "kubernetes_manifest" "eks_access_lab_rolebindings" {
  count    = length(local.eks_access_lab_rolebindings)
  manifest = local.eks_access_lab_rolebindings[count.index]

  depends_on = [kubernetes_manifest.eks_access_lab_namespaces]
}
