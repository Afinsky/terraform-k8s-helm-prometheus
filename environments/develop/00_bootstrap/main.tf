locals {
  common_tags = merge({
    "client"      = "K8S practice"
    "project"     = "K8S"
    "environment" = var.environment
    "owner"       = "me"
    "Terraform"   = "true"
  })

  project_name  = "me"
  resource_name = "${var.environment}-${local.project_name}"
}

provider "aws" {
  region                   = "us-east-1" #eu-west-1
  shared_config_files      = ["$HOME/.aws/config"]
  shared_credentials_files = ["$HOME/.aws/credentials"]
  profile                  = var.profile

  #   assume_role {
  #     role_arn = var.role_arn
  #   }
}

module "backend" {
  source = "./../../../modules/backend"

  name_terrafrom_state_s3              = "${local.resource_name}-terraform-state"
  versioning                           = { status = true }
  server_side_encryption_configuration = { rule = { apply_server_side_encryption_by_default = { sse_algorithm = "AES256" } } }
  tags                                 = local.common_tags
}
