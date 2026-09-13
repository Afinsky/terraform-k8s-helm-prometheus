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
  aws_service_access_principals = ["sso.amazonaws.com"]
}
