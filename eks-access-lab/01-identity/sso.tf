locals {
  instance_arn      = tolist(data.aws_ssoadmin_instances.this.arns)[0]
  identity_store_id = tolist(data.aws_ssoadmin_instances.this.identity_store_ids)[0]
}

# ============================================================
# Группы и пользователи (в реальной компании приезжали бы из Okta по SCIM)
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
# У identitystore нет API/ресурса, чтобы задать пароль созданному
# пользователю (то самое "Generate one-time password" из консоли).
# После apply: Identity Center → User → Reset password → Generate
# one-time password для каждого из трёх юзеров.
# ------------------------------------------------------------------

# ============================================================
# PlatformAdmin — твой доступ, AdministratorAccess на весь аккаунт
# ============================================================
resource "aws_ssoadmin_permission_set" "platform_admin" {
  name             = "PlatformAdmin"
  instance_arn     = local.instance_arn
  session_duration = "PT4H"
  tags             = local.common_tags
}

resource "aws_ssoadmin_managed_policy_attachment" "platform_admin" {
  instance_arn       = local.instance_arn
  permission_set_arn = aws_ssoadmin_permission_set.platform_admin.arn
  managed_policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

resource "aws_ssoadmin_account_assignment" "platform_admin" {
  instance_arn       = local.instance_arn
  permission_set_arn = aws_ssoadmin_permission_set.platform_admin.arn
  principal_type     = "GROUP"
  principal_id       = aws_identitystore_group.groups["platform-admins"].group_id
  target_type        = "AWS_ACCOUNT"
  target_id          = data.aws_caller_identity.current.account_id

  depends_on = [aws_ssoadmin_managed_policy_attachment.platform_admin]
}

# ============================================================
# EKSDev-Payments / EKSDev-Search — минимальная IAM-политика:
# только узнать, что кластер существует и где он.
# Это НЕ даёт никаких прав внутри Kubernetes — то отдельно, в access entries
# (Фаза 3, стек 02-cluster).
# ============================================================
resource "aws_ssoadmin_permission_set" "eks_dev" {
  for_each         = local.teams
  name             = each.value.permission_set
  instance_arn     = local.instance_arn
  session_duration = "PT1H" # 1 час. Коротко специально, пригодится в Фазе 7
  tags             = local.common_tags
}

resource "aws_ssoadmin_permission_set_inline_policy" "eks_dev" {
  for_each           = local.teams
  instance_arn       = local.instance_arn
  permission_set_arn = aws_ssoadmin_permission_set.eks_dev[each.key].arn

  inline_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["eks:DescribeCluster", "eks:ListClusters"]
      Resource = "*"
    }]
  })
}

# Назначение: "группа X может входить в аккаунт Y с permission set Z".
# В этот момент в аккаунте появляется роль AWSReservedSSO_EKSDev-..._<хвост>
resource "aws_ssoadmin_account_assignment" "eks_dev" {
  for_each           = local.teams
  instance_arn       = local.instance_arn
  permission_set_arn = aws_ssoadmin_permission_set.eks_dev[each.key].arn
  principal_type     = "GROUP"
  principal_id       = aws_identitystore_group.groups[each.value.group].group_id
  target_type        = "AWS_ACCOUNT"
  target_id          = data.aws_caller_identity.current.account_id

  depends_on = [aws_ssoadmin_permission_set_inline_policy.eks_dev]
}
