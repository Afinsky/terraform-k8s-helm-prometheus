# Generic permission-set engine: one declarative table (local.permission_sets)
# drives N permission sets, their policies, and their account assignments —
# accounts are matched by name regex against the Organization's live account
# list (data.tf), not hardcoded IDs. Add an account in accounts.tf and any
# permission set whose account_patterns match its name picks it up on the
# next apply, no other edit needed.
#  (setproduct(groups, account_ids) → for_each
# assignments) collapsed into a single stack instead of a separate module,
# since this repo has no per-permission-set Terragrunt units to wrap.
locals {
  # name => id for every ACTIVE account in the org, management account
  # included (it's a member of the org root OU too).
  org_accounts = {
    for acct in data.aws_organizations_organizational_unit_descendant_accounts.all.accounts :
    acct.name => acct.id
    if acct.status == "ACTIVE"
  }

  permission_sets = {
    # Parity with the account's own IAM Identity Center admin: full admin,
    # but only on the management account itself — account_patterns is
    # anchored so it can never accidentally widen onto a future workloads-*
    # account.
    platform-admin = {
      description      = "Full admin on the management account."
      group            = "platform-admins"
      session_duration = "PT4H"
      account_patterns = ["^abotyan001-root$"]
      managed_policies = ["arn:aws:iam::aws:policy/AdministratorAccess"]
    }

    # Every account in the org, management account included — matches
    # whatever accounts.tf vends next without editing this file again.
    devops-admin = {
      description      = "DevOps admin on every account in the org."
      group            = "devops-admins"
      session_duration = "PT1H" # short: comes in handy in Phase 7
      account_patterns = [".*"]
      managed_policies = ["arn:aws:iam::aws:policy/AdministratorAccess"]
      # inline_policy = jsonencode({
      #   Version = "2012-10-17"
      #   Statement = [{
      #     Effect   = "Allow"
      #     Action   = ["eks:DescribeCluster", "eks:ListClusters"]
      #     Resource = "*"
      #   }]
      # })
    }

    developer = {
      description      = "Read-only + EKS discovery, workloads-dev only."
      group            = "developers"
      session_duration = "PT1H"
      account_patterns = ["^workloads-dev$"]
      managed_policies = ["arn:aws:iam::aws:policy/ReadOnlyAccess"]
      inline_policy = jsonencode({
        Version = "2012-10-17"
        Statement = [{
          Effect   = "Allow"
          Action   = ["eks:DescribeCluster", "eks:ListClusters"]
          Resource = "*"
        }]
      })
    }
  }

  # permission_set key -> list of matched account IDs.
  permission_set_accounts = {
    for ps_key, spec in local.permission_sets : ps_key => [
      for name, id in local.org_accounts : id
      if anytrue([for pattern in spec.account_patterns : can(regex(pattern, name))])
    ]
  }

  # Flattened "permission_set x account" pairs, one map key per assignment —
  # the setproduct(groups, account_ids) idea from ,
  # done directly since each permission set here has exactly one group.
  permission_set_assignments = merge([
    for ps_key, account_ids in local.permission_set_accounts : {
      for account_id in account_ids : "${ps_key}_${account_id}" => {
        permission_set = ps_key
        account_id     = account_id
      }
    }
  ]...)

  # permission_set x managed_policy pairs.
  permission_set_managed_policies = merge([
    for ps_key, spec in local.permission_sets : {
      for policy_arn in try(spec.managed_policies, []) : "${ps_key}_${policy_arn}" => {
        permission_set = ps_key
        policy_arn     = policy_arn
      }
    }
  ]...)
}

resource "aws_ssoadmin_permission_set" "generated" {
  for_each = local.permission_sets

  name             = each.key
  description      = each.value.description
  instance_arn     = local.instance_arn
  session_duration = each.value.session_duration
  tags             = local.common_tags
}

resource "aws_ssoadmin_managed_policy_attachment" "generated" {
  for_each = local.permission_set_managed_policies

  instance_arn       = local.instance_arn
  permission_set_arn = aws_ssoadmin_permission_set.generated[each.value.permission_set].arn
  managed_policy_arn = each.value.policy_arn
}

resource "aws_ssoadmin_permission_set_inline_policy" "generated" {
  for_each = { for ps_key, spec in local.permission_sets : ps_key => spec.inline_policy if try(spec.inline_policy, null) != null }

  instance_arn       = local.instance_arn
  permission_set_arn = aws_ssoadmin_permission_set.generated[each.key].arn
  inline_policy      = each.value
}

# "group X can sign into account Y with permission set Z" — this is the
# point where the role AWSReservedSSO_<permission-set-name>_<suffix>
# appears in account Y.
resource "aws_ssoadmin_account_assignment" "generated" {
  for_each = local.permission_set_assignments

  instance_arn       = local.instance_arn
  permission_set_arn = aws_ssoadmin_permission_set.generated[each.value.permission_set].arn
  principal_type     = "GROUP"
  principal_id       = aws_identitystore_group.groups[local.permission_sets[each.value.permission_set].group].group_id
  target_type        = "AWS_ACCOUNT"
  target_id          = each.value.account_id

  depends_on = [
    aws_ssoadmin_managed_policy_attachment.generated,
    aws_ssoadmin_permission_set_inline_policy.generated,
  ]
}
