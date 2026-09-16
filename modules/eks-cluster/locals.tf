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

  # Referenced both by module.eks's own `name` and by the node groups' CA
  # discovery tags below - can't use module.eks.cluster_name for the latter,
  # that would be a self-reference (the tags are an input to module.eks).
  cluster_name = "${local.resource_name}-k8s-cluster"

  # Cluster Autoscaler (modules/eks-workloads/cluster-autoscaler.tf)
  # discovers which ASGs it's allowed to scale by these tags - standard
  # upstream convention, also what its IAM policy's ResourceTag condition
  # matches against.
  cluster_autoscaler_tags = {
    "k8s.io/cluster-autoscaler/enabled"               = "true"
    "k8s.io/cluster-autoscaler/${local.cluster_name}" = "owned"
  }

  # Root-account break-glass admin entry: grants cluster-admin to this
  # account's root ARN directly, independent of Identity Center/SSO - a
  # fallback that still works if the SSO-based devops-admin access entry
  # (eks.tf) or permission_sets.tf ever gets misconfigured or SSO itself is
  # down. "viewer" is a currently-unused persona (empty user_arn list, so it
  # produces no entries) - the SSO "developer" permission set's own access
  # entry (eks-access.tf) already covers cluster-wide read-only, but the
  # shape is kept here in case a non-SSO read-only principal is ever needed.
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
