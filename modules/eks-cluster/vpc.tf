################################################################################
# VPC
################################################################################

# Registry source, not a raw git URL - a pinned exact version here is
# already immutable (the registry doesn't let a published version move) and
# checksummed via .terraform.lock.hcl, same supply-chain guarantee a
# commit-hash-pinned git ref would give.
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "v6.6.1"

  name                          = local.vpc.homelab.name
  create_database_subnet_group  = false
  manage_default_route_table    = false
  manage_default_security_group = false
  # Required for a private EKS API endpoint to actually resolve to a
  # VPC-reachable address (AWS requires both enable_dns_support AND
  # enable_dns_hostnames = true) - false here caused nodes to fall back to
  # public/unreachable DNS answers and time out joining the cluster.
  enable_dns_hostnames    = true
  map_public_ip_on_launch = false
  #Note that the order of the list of availability zones is associated with the order of the list of subnets
  cidr             = local.vpc.homelab.cidr
  azs              = local.vpc.homelab.azs
  private_subnets  = local.vpc.homelab.private_subnets
  public_subnets   = local.vpc.homelab.public_subnets
  database_subnets = local.vpc.homelab.database_subnets

  enable_nat_gateway         = true
  manage_default_network_acl = true
  default_network_acl_name   = local.vpc.homelab.default_network_acl_name

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

  enable_flow_log                                 = local.vpc.homelab.enable_flow_log
  create_flow_log_cloudwatch_log_group            = local.vpc.homelab.enable_flow_log
  create_flow_log_cloudwatch_iam_role             = local.vpc.homelab.enable_flow_log
  flow_log_cloudwatch_log_group_retention_in_days = local.vpc.homelab.flow_log_cloudwatch_log_group_retention_in_days
  flow_log_traffic_type                           = "ALL"
  flow_log_cloudwatch_log_group_name_prefix       = local.vpc.homelab.flow_log_cloudwatch_log_group_name_prefix

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
