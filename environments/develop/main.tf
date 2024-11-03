provider "aws" {
  region                   = local.region
  shared_config_files      = ["$HOME/.aws/config"]
  shared_credentials_files = ["$HOME/.aws/credentials"]
  profile                  = var.profile
}

data "aws_availability_zones" "available" {}

locals {
  name   = "ex-self-mng"
  region = "us-east-1"

  vpc_cidr = "10.0.0.0/16"
  azs      = slice(data.aws_availability_zones.available.names, 0, 3)

  tags = {
    Example    = local.name
    GithubRepo = "terraform-aws-eks"
    GithubOrg  = "terraform-aws-modules"
  }

  common_tags = merge({
    "coherent:client"      = "K8S practice"
    "coherent:project"     = "K8S"
    "coherent:environment" = var.environment
    "coherent:owner"       = "AlexeyBotyan@coherentsolutions.com"
    "Terraform"            = "true"
  })

  project_name  = "abotyan"
  resource_name = "${var.environment}-${local.project_name}"

  log_retention_in_days = 365 # Days

  VPC = {
    csai = {
      name                                            = "${local.resource_name}-vpc"
      default_network_acl_name                        = "${local.resource_name}-acl"
      cidr                                            = var.VPC.csai.cidr
      azs                                             = var.VPC.csai.azs
      private_subnets                                 = var.VPC.csai.private_subnets
      public_subnets                                  = var.VPC.csai.public_subnets
      database_subnets                                = var.VPC.csai.database_subnets
      enable_flow_log                                 = var.enable_flow_log
      create_flow_log_cloudwatch_log_group            = var.enable_flow_log
      create_flow_log_cloudwatch_iam_role             = var.enable_flow_log
      flow_log_cloudwatch_log_group_name_prefix       = "/aws/vpc-flow-log/${local.resource_name}-vpc/"
      flow_log_cloudwatch_log_group_retention_in_days = local.log_retention_in_days
    }
  }
}

################################################################################
# VPC
################################################################################

module "vpc" {
  source = "github.com/terraform-aws-modules/terraform-aws-vpc?ref=v5.1.1"

  name                          = local.VPC.csai.name
  create_database_subnet_group  = false
  manage_default_route_table    = false
  manage_default_security_group = false
  enable_dns_hostnames          = false
  map_public_ip_on_launch       = true
  #Note that the order of the list of availability zones is associated with the order of the list of subnets
  cidr             = local.VPC.csai.cidr
  azs              = local.VPC.csai.azs
  private_subnets  = local.VPC.csai.private_subnets
  public_subnets   = local.VPC.csai.public_subnets
  database_subnets = local.VPC.csai.database_subnets

  enable_nat_gateway = true

  manage_default_network_acl = true
  default_network_acl_name   = local.VPC.csai.default_network_acl_name

  default_network_acl_ingress = [
    {
      rule_no    = 100
      action     = "allow"
      from_port  = 0
      to_port    = 0
      protocol   = "-1"
      cidr_block = "0.0.0.0/0"
    }
  ]

  default_network_acl_egress = [
    {
      rule_no    = 100
      action     = "allow"
      from_port  = 0
      to_port    = 0
      protocol   = "-1"
      cidr_block = "0.0.0.0/0"
    }
  ]

  enable_flow_log                                 = local.VPC.csai.enable_flow_log
  create_flow_log_cloudwatch_log_group            = local.VPC.csai.enable_flow_log
  create_flow_log_cloudwatch_iam_role             = local.VPC.csai.enable_flow_log
  flow_log_cloudwatch_log_group_retention_in_days = local.VPC.csai.flow_log_cloudwatch_log_group_retention_in_days
  flow_log_traffic_type                           = "ALL"
  flow_log_cloudwatch_log_group_name_prefix       = local.VPC.csai.flow_log_cloudwatch_log_group_name_prefix

  vpc_flow_log_tags = merge({ Name = local.resource_name }, local.common_tags)

  public_subnet_tags = {
    "kubernetes.io/role/elb" = 1
  }

  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = 1
  }

  tags = local.common_tags
}