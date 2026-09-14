# The "terraform" static IAM user never talks to member accounts directly.
# It assumes this role instead, and this role is the only principal that
# account-access-stackset.tf's terraform-target trusts. That indirection is
# the whole point: terraform-target's trust policy names one specific role
# ARN, not this account's ":root" (what AWS Organizations' own default
# OrganizationAccountAccessRole trusts) — so a future SSO permission set in
# this account with a wide sts:AssumeRole grant still can't reach into any
# member account through this door, only whatever explicitly gets
# sts:AssumeRole on this role's own ARN (nothing does, other than the
# "terraform" user below).
data "aws_iam_user" "terraform" {
  user_name = "terraform"
}

resource "aws_iam_role" "terraform_management" {
  name        = "terraform-management"
  description = "Assumed by the \"terraform\" static IAM user; the only principal terraform-target (in every member account) trusts."

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { AWS = data.aws_iam_user.terraform.arn }
    }]
  })

  tags = local.common_tags
}

# Single purpose: reach terraform-target in any member account. Nothing else —
# account creation, Identity Center and the StackSet itself stay under the
# "terraform" user directly, so this role's blast radius is exactly one
# sts:AssumeRole call.
resource "aws_iam_role_policy" "terraform_management" {
  name = "assume-terraform-target"
  role = aws_iam_role.terraform_management.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid      = "AssumeTerraformTargetInAnyMemberAccount"
      Effect   = "Allow"
      Action   = "sts:AssumeRole"
      Resource = "arn:aws:iam::*:role/terraform-target"
    }]
  })
}
