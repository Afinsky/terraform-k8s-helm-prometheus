################################################################################
# VPC
################################################################################

locals {
  common_tags = merge(
    {
      "client"      = "K8S practice"
      "project"     = "K8S"
      "environment" = var.environment
      "owner"       = "me"
      "Terraform"   = "true"
    }
  )

  project_name          = "me"
  resource_name         = "${var.environment}-${local.project_name}"
  log_retention_in_days = 365 # Days

  vpc = {
    homelab = {
      name                                            = "${local.resource_name}-vpc"
      default_network_acl_name                        = "${local.resource_name}-acl"
      cidr                                            = var.vpc.homelab.cidr
      azs                                             = var.vpc.homelab.azs
      private_subnets                                 = var.vpc.homelab.private_subnets
      public_subnets                                  = var.vpc.homelab.public_subnets
      database_subnets                                = var.vpc.homelab.database_subnets
      enable_flow_log                                 = var.enable_flow_log
      create_flow_log_cloudwatch_log_group            = var.enable_flow_log
      create_flow_log_cloudwatch_iam_role             = var.enable_flow_log
      flow_log_cloudwatch_log_group_name_prefix       = "/aws/vpc-flow-log/${local.resource_name}-vpc/"
      flow_log_cloudwatch_log_group_retention_in_days = local.log_retention_in_days
    }
  }
}

##############################################################################
#  EKS
##############################################################################

locals {
  prefix = "${local.project_name}-${var.environment}-${var.region}"

  eks_access_entries = flatten(
    [
      for k, v in {
        viewer = {
          user_arn = []
        }
        admin = {
          user_arn = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"]
        }
        } : [
        for s in v.user_arn : {
          username = s, access_policy = local.eks_access_policy[k], group = k
        }
      ]
    ]
  )

  eks_access_policy = {
    viewer = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSViewPolicy",
    admin  = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
  }
}

##############################################################################
#  Route53
##############################################################################
# Zone lives in the management account (modules/identity-center/dns.tf), not this
# one — id/name come in as inputs instead of a local data lookup.

locals {
  zone_id   = var.dns_zone_id
  zone_name = var.dns_zone_name
}
