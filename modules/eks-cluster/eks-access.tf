# EKS access for the Identity Center SSO roles that aren't the day-to-day
# admin identity (devops-admin gets its own access entry directly in eks.tf,
# since a principal can only have one access entry per cluster and it needs
# the cluster-admin association unconditionally). Looked up by name regex,
# not remote state or hardcoded ARNs - see modules/identity-center/permission_sets.tf.

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
  # devops-admin itself is NOT one of these - see eks.tf for why.
  sso_access_entries_all = {
    "platform-admin" = {
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
    # modules/identity-center/{sso,permission_sets}.tf): cluster-wide
    # read-only, nothing more.
    "developer" = {
      kubernetes_groups = []
      principal_arn     = local.sso_role_arn.developer
      policy_associations = {
        view = {
          policy_arn = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSViewPolicy"
          access_scope = {
            type = "cluster"
          }
        }
      }
    }
  }

  sso_access_entries = {
    for k, v in local.sso_access_entries_all : k => v if v.principal_arn != null
  }
}
