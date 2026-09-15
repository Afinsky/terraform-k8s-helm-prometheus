output "cluster_name" {
  value       = module.eks.cluster_name
  description = "The name of the created EKS cluster."
}

output "cluster_version" {
  value       = module.eks.cluster_version
  description = "The version of Kubernetes running on the EKS cluster."
}

output "cluster_endpoint" {
  value       = module.eks.cluster_endpoint
  description = "The endpoint for the EKS Kubernetes API server."
}

output "access_entries" {
  value       = module.eks.access_entries
  description = "Map of access entries created and their attributes."
}

output "oidc_provider" {
  value       = module.eks.oidc_provider
  description = "The OpenID Connect identity provider (issuer URL without leading `https://`)."
}

output "oidc_provider_arn" {
  value       = module.eks.oidc_provider_arn
  description = "The ARN of the OIDC Provider for the EKS cluster."
}

output "cluster_certificate_authority_data" {
  value       = module.eks.cluster_certificate_authority_data
  description = "Base64-encoded CA cert for the cluster - modules/eks-workloads' kubernetes/helm providers need this to authenticate."
}

output "vpc_id" {
  value       = module.vpc.vpc_id
  description = "VPC ID - consumed by modules/eks-workloads' aws-load-balancer-controller (needs to know which VPC to find subnets/security groups in)."
}

output "acm_certificate_arn" {
  value       = aws_acm_certificate_validation.backend.certificate_arn
  description = "ARN of the validated backend ACM certificate - consumed by modules/eks-workloads' ingress-nginx Service annotation."
}
