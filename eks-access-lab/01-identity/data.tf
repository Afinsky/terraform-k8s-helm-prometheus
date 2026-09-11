data "aws_caller_identity" "current" {}

# ------------------------------------------------------------------
# Между apply #1 (organization.tf) и apply #2 (этот data-источник)
# нужен ручной шаг: включить IAM Identity Center в консоли. У провайдера
# AWS нет ресурса, который включает Identity Center как organization
# instance, поэтому этот data-источник иначе просто ничего не найдёт.
# См. README.md.
# ------------------------------------------------------------------
data "aws_ssoadmin_instances" "this" {}
