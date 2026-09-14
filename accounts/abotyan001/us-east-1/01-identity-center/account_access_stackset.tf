# Auto-provisions the "terraform-target" IAM role into every account of this
# Organization — present ones and any created later by accounts.tf — with NO
# manual step: no console login into the member account, no `terraform
# import`, no post-hoc trust-policy edit.
#
# This is the only way to get a CUSTOM trust policy onto a brand-new AWS
# account's day-1 access role. `aws_organizations_account` always has AWS
# create its own default role (OrganizationAccountAccessRole, trusting this
# account's ":root") — there is no argument on that resource to change what
# it trusts. A CloudFormation StackSet with SERVICE_MANAGED permissions and
# auto_deployment is the one AWS-native mechanism that reacts to "an account
# just joined this OU" and deploys arbitrary resources into it automatically
# — including a role with whatever trust policy we actually want. The
# account-vending side (accounts.tf) and this StackSet are independent:
# order between them doesn't matter, and this also backfills the role into
# abotyan001's org root — SERVICE_MANAGED targeting the org root itself, not
# a specific sub-OU, so no OU structure has to exist first.
# SERVICE_MANAGED requires two separate switches: Organizations trusted
# access for member.org.stacksets.cloudformation.amazonaws.com
# (organization.tf — Terraform-managed) AND CloudFormation's own
# Organizations-access activation, which has no Terraform resource and must
# be run once by hand from the management account — see this layer's
# README.md, "Order of operations", step 3.
resource "aws_cloudformation_stack_set" "terraform_target" {
  name             = "terraform-target-role"
  description      = "Provisions the terraform-target IAM role in every account of this Organization, trusting terraform-management (in the management account) only."
  permission_model = "SERVICE_MANAGED"
  capabilities     = ["CAPABILITY_NAMED_IAM"]

  auto_deployment {
    enabled                          = true
    retain_stacks_on_account_removal = false
  }

  template_body = jsonencode({
    AWSTemplateFormatVersion = "2010-09-09"
    Description              = "terraform-target: assumable only by terraform-management in the Organization's management account."
    Resources = {
      TerraformTargetRole = {
        Type = "AWS::IAM::Role"
        Properties = {
          RoleName = "terraform-target"
          AssumeRolePolicyDocument = {
            Version = "2012-10-17"
            Statement = [{
              Effect    = "Allow"
              Action    = "sts:AssumeRole"
              Principal = { AWS = aws_iam_role.terraform_management.arn }
            }]
          }
          # AdministratorAccess here mirrors what AWS's own
          # OrganizationAccountAccessRole grants by default — this account is
          # a personal lab. Narrow this (and drop ManagedPolicyArns for an
          # inline/managed policy scoped to what `develop` actually needs)
          # once this is more than a lab.
          ManagedPolicyArns = ["arn:aws:iam::aws:policy/AdministratorAccess"]
        }
      }
    }
  })

  depends_on = [aws_organizations_organization.this]
}

# SERVICE_MANAGED stack instances are declared against deployment_targets
# (OUs), not individual accounts — that's what makes this apply to accounts
# that don't exist yet. Targeting the org's own root, since there's no
# sub-OU structure in this lab.
resource "aws_cloudformation_stack_set_instance" "terraform_target" {
  stack_set_name = aws_cloudformation_stack_set.terraform_target.name

  deployment_targets {
    organizational_unit_ids = [aws_organizations_organization.this.roots[0].id]
  }

  operation_preferences {
    max_concurrent_percentage    = 100
    failure_tolerance_percentage = 30
  }
}
