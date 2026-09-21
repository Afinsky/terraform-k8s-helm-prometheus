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
  description      = "Provisions terraform-target and github-actions-plan-target IAM roles in every account of this Organization."
  permission_model = "SERVICE_MANAGED"
  capabilities     = ["CAPABILITY_NAMED_IAM"]

  auto_deployment {
    enabled                          = true
    retain_stacks_on_account_removal = false
  }

  template_body = jsonencode({
    AWSTemplateFormatVersion = "2010-09-09"
    Description              = "terraform-target: assumable only by terraform-management. github-actions-plan-target: assumable only by github-actions-plan (github_oidc.tf) - both in the Organization's management account."
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
          # OrganizationAccountAccessRole grants by default. Broader than
          # what eks-cluster/eks-workloads actually need (VPC/EKS/ACM/ECR
          # and IRSA role management) - narrowing this to a scoped
          # inline/managed policy is still a TODO, not done yet.
          ManagedPolicyArns = ["arn:aws:iam::aws:policy/AdministratorAccess"]
        }
      }
      # Read-only counterpart to TerraformTargetRole, same chained-trust
      # shape (see github_oidc.tf's comment) - lets .github/workflows/plan.yml
      # plan a member account's layers (workloads-dev's eks-cluster/
      # eks-workloads) without ever holding admin credentials for it.
      GithubActionsPlanTargetRole = {
        Type = "AWS::IAM::Role"
        Properties = {
          RoleName = "github-actions-plan-target"
          AssumeRolePolicyDocument = {
            Version = "2012-10-17"
            Statement = [{
              Effect    = "Allow"
              Action    = "sts:AssumeRole"
              Principal = { AWS = aws_iam_role.github_actions_plan.arn }
            }]
          }
          ManagedPolicyArns = ["arn:aws:iam::aws:policy/ReadOnlyAccess"]
          # ReadOnlyAccess alone doesn't include sts:AssumeRole. A member
          # account's modules/eks-cluster (e.g. workloads-dev's) has an
          # aws.dns provider that assumes dns-zone-writer, back in this
          # (management) account, to preview the ACM DNS-validation record
          # diff - dns.tf's trust condition lists this role by name for that
          # reason. Not a write-capability escalation: dns-zone-writer's own
          # permissions are what could write to Route53, and `terragrunt
          # plan` never calls them.
          Policies = [{
            PolicyName = "assume-dns-zone-writer"
            PolicyDocument = {
              Version = "2012-10-17"
              Statement = [{
                Sid      = "AssumeDnsZoneWriter"
                Effect   = "Allow"
                Action   = "sts:AssumeRole"
                Resource = aws_iam_role.dns_zone_writer.arn
              }]
            }
          }]
        }
      }
    }
  })

  depends_on = [aws_organizations_organization.this]
}

# SERVICE_MANAGED stack instances are declared against deployment_targets
# (OUs), not individual accounts — that's what makes this apply to accounts
# that don't exist yet. Targeting the org's own root, since there's no
# sub-OU structure — every account sits directly under the org root.
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
