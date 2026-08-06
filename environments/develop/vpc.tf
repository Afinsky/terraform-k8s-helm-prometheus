################################################################################
# VPC
################################################################################

module "vpc" {
  source = "github.com/terraform-aws-modules/terraform-aws-vpc?ref=v5.1.1"

  name                          = local.vpc.csai.name
  create_database_subnet_group  = false
  manage_default_route_table    = false
  manage_default_security_group = false
  enable_dns_hostnames          = false
  map_public_ip_on_launch       = true
  #Note that the order of the list of availability zones is associated with the order of the list of subnets
  cidr             = local.vpc.csai.cidr
  azs              = local.vpc.csai.azs
  private_subnets  = local.vpc.csai.private_subnets
  public_subnets   = local.vpc.csai.public_subnets
  database_subnets = local.vpc.csai.database_subnets

  enable_nat_gateway         = true
  manage_default_network_acl = true
  default_network_acl_name   = local.vpc.csai.default_network_acl_name

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

  enable_flow_log                                 = local.vpc.csai.enable_flow_log
  create_flow_log_cloudwatch_log_group            = local.vpc.csai.enable_flow_log
  create_flow_log_cloudwatch_iam_role             = local.vpc.csai.enable_flow_log
  flow_log_cloudwatch_log_group_retention_in_days = local.vpc.csai.flow_log_cloudwatch_log_group_retention_in_days
  flow_log_traffic_type                           = "ALL"
  flow_log_cloudwatch_log_group_name_prefix       = local.vpc.csai.flow_log_cloudwatch_log_group_name_prefix

  public_subnet_tags = {
    "kubernetes.io/role/elb" = 1
  }

  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = 1
  }

  vpc_flow_log_tags = merge(
    {
      Name = local.resource_name
    },
    local.common_tags
  )

  tags = local.common_tags
}
