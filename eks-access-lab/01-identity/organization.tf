# AWS Organizations — единственная зависимость, без которой Identity Center
# не сможет выдавать роли в AWS-аккаунты (режим "account instance" этого
# не умеет вообще). Применяется первым, отдельно:
#   terraform apply -target=aws_organizations_organization.this
resource "aws_organizations_organization" "this" {
  feature_set = "ALL"

  # AWS сама прописывает sso.amazonaws.com в trusted access при
  # "Enable IAM Identity Center → Enable with AWS Organizations".
  # Если не объявить это здесь явно, Terraform на следующем apply
  # попытается убрать этот principal и отвяжет Identity Center
  # от организации.
  aws_service_access_principals = ["sso.amazonaws.com"]
}
