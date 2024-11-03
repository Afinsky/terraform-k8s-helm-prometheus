locals {
  common_tags = merge({
    "coherent:client"      = "K8S practice"
    "coherent:project"     = "K8S"
    "coherent:environment" = var.environment
    "coherent:owner"       = "AlexeyBotyan@coherentsolutions.com"
    "Terraform"            = "true"
  })

  project_name  = "abotyan"
  resource_name = "${var.environment}-${local.project_name}"
}

variable "profile" {
  description = "AWS Profile name"
  type        = string
}

variable "environment" {
  description = "Environment"
  type        = string
}

variable "vanta_tags" {
  description = "Vanta tags"
  type        = map(string)
  default     = {}
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
  name_lock_dynamodb                   = "${local.resource_name}-terraform-state-locks"
  versioning                           = { status = true }
  server_side_encryption_configuration = { rule = { apply_server_side_encryption_by_default = { sse_algorithm = "AES256" } } }
  tags                                 = local.common_tags
}

output "terraform_state_bucket_id" {
  value = module.backend.terraform_state_bucket_id
}
output "terraform_state_dynamodb_table_id" {
  value = module.backend.terraform_state_dynamodb_table_id
}