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

  # guard against applying against the wrong AWS account/profile
  allowed_account_ids = [var.aws_account_id]

  #   assume_role {
  #     role_arn = var.role_arn
  #   }
}

module "backend" {
  # self-contained under this stack (not ../../modules/backend) — Terragrunt always runs Terraform from a
  # copy staged under .terragrunt-cache, so a source reaching outside this directory would need a path
  # whose depth isn't stable across staging; a subdirectory of this unit stages along with it.
  source = "./modules/backend"

  name_terrafrom_state_s3              = "${local.resource_name}-terraform-state"
  versioning                           = { status = true }
  server_side_encryption_configuration = { rule = { apply_server_side_encryption_by_default = { sse_algorithm = "AES256" } } }
  tags                                 = local.common_tags
}
