locals {
  instance_arn      = tolist(data.aws_ssoadmin_instances.this.arns)[0]
  identity_store_id = tolist(data.aws_ssoadmin_instances.this.identity_store_ids)[0]
}

# ============================================================
# Groups and users (in a real company these would arrive from Okta via SCIM)
#
# A group by itself carries no AWS permissions at all - it's just a named
# list of members here, same as in any directory service. Permissions only
# exist once a group is used as the `principal_id` of an
# aws_ssoadmin_account_assignment (permission_sets.tf) - that's the one place
# a group, a permission set, and a target account get bound together, and
# it's what makes AWS auto-provision the actual IAM role
# (AWSReservedSSO_<permission-set-name>_<suffix>) inside that account.
# ============================================================
resource "aws_identitystore_group" "groups" {
  for_each          = local.groups
  identity_store_id = local.identity_store_id
  display_name      = each.key
  description       = "${local.resource_name}: ${each.key}"
}

resource "aws_identitystore_user" "users" {
  for_each          = local.users
  identity_store_id = local.identity_store_id
  display_name      = each.key
  user_name         = each.key

  name {
    given_name  = each.value.given_name
    family_name = each.value.family_name
  }

  emails {
    value   = each.value.email
    primary = true
  }
}

resource "aws_identitystore_group_membership" "users" {
  for_each          = local.users
  identity_store_id = local.identity_store_id
  group_id          = aws_identitystore_group.groups[each.value.group].group_id
  member_id         = aws_identitystore_user.users[each.key].user_id
}

# ------------------------------------------------------------------
# identitystore has no API/resource to set a password for a created user
# (that's the console's "Generate one-time password"). After apply:
# Identity Center → User → Reset password → Generate one-time password
# for each of the three users.
# ------------------------------------------------------------------

# Permission sets, their policies, and their account assignments are
# generated from local.permission_sets — see permission_sets.tf.
