data "aws_caller_identity" "current" {}

data "aws_eks_cluster_auth" "eks" {
  name = module.eks.cluster_name
}

data "aws_route53_zone" "zone" {
  name         = local.zone_name
  private_zone = false
}
