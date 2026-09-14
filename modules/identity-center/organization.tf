# AWS Organizations — the only dependency without which Identity Center
# can't grant roles into AWS accounts ("account instance" mode can't do
# this at all). Applied first, on its own:
#   terragrunt apply -target=aws_organizations_organization.this
resource "aws_organizations_organization" "this" {
  feature_set = "ALL"

  # AWS itself registers sso.amazonaws.com as trusted access when you
  # "Enable IAM Identity Center → Enable with AWS Organizations". If we
  # don't declare it here explicitly, Terraform will try to remove this
  # principal on the next apply and unlink Identity Center from the
  # organization.
  #
  # member.org.stacksets.cloudformation.amazonaws.com is what lets
  # account-access-stackset.tf's StackSet use SERVICE_MANAGED permissions —
  # ie. auto-deploy the terraform-target role into every account of this
  # Organization (including ones that don't exist yet) without us ever
  # having to log into them or hand-manage a per-account IAM role.
  aws_service_access_principals = [
    "sso.amazonaws.com",
    "member.org.stacksets.cloudformation.amazonaws.com",
  ]
}
