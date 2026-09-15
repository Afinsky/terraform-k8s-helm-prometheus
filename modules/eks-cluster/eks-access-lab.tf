# PLAT-101 lab, Phase 3: EKS access via IAM Identity Center SSO roles +
# Kubernetes RBAC, instead of static IAM users. search-dev stands in for a
# separate environment per the lab brief - payments-dev/payments-prod are now
# unused (there's no permission set left mapped to a "payments" persona,
# see permission_sets.tf's platform-admin/devops-admin/developer). This
# reuses the existing dev cluster instead of a dedicated one - same
# account/region, and the access-entry/RBAC pattern doesn't need its own
# infrastructure to be meaningful.
#
# Identity side (groups/users/permission sets) lives in modules/identity-center.
# This file only consumes what it creates, by looking up the resulting IAM
# roles - no remote state, no hardcoded ARNs.

locals {
  # SSO role names carry a random suffix that changes if the permission
  # set's account assignment is ever recreated - look roles up by name
  # regex instead of hardcoding the ARN. Permission set names come from
  # modules/identity-center/permission_sets.tf: platform-admin/devops-admin/
  # developer.
  sso_role_patterns = {
    platform_admin = "AWSReservedSSO_platform-admin_.*"
    devops_admin   = "AWSReservedSSO_devops-admin_.*"
    developer      = "AWSReservedSSO_developer_.*"
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

  # Not every permission set above is assigned to every account this module
  # runs in (platform-admin, in particular, is deliberately scoped to just
  # the management account - see modules/identity-center/permission_sets.tf) -
  # filtered out below rather than erroring, so this file works unmodified
  # in an account with only 2 of the 3 roles.
  #
  # devops-admin itself is NOT one of these - it's the real day-to-day admin
  # identity (permission_sets.tf grants it in every account), so it gets a
  # genuine cluster-admin access entry directly in eks.tf instead of a
  # namespace-scoped lab persona here. A principal can only have one access
  # entry per cluster - reusing it for a lab persona here would conflict
  # with that entry.
  lab_access_entries_all = {
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
    # alice (member of the "developers" Identity Center group, which is what
    # the "developer" permission set is assigned to - see
    # modules/identity-center/{sso,permission_sets}.tf): no access policy at
    # all here - every right she has in search-dev comes from the RoleBinding
    # below, purely via RBAC. "developers" is the real Identity Center group
    # name - the old "search-devs" name didn't correspond to anything.
    "eks-access-lab-developer" = {
      kubernetes_groups = ["developers"]
      principal_arn     = local.sso_role_arn.developer
    }
  }

  lab_access_entries = {
    for k, v in local.lab_access_entries_all : k => v if v.principal_arn != null
  }
}

# The namespaces standing in for "environments" and the RBAC RoleBindings
# that pair with the access entries above are Kubernetes-side, not
# AWS-IAM-side — see modules/eks-workloads/eks-access-lab.tf.
