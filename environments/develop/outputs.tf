output "vpc_id" {
  value       = module.vpc.vpc_id
  description = <<-EOT
    ID of the VPC. Paste into
    gitops/platform/aws-load-balancer-controller/values-develop.yaml's
    `vpcId` after first apply (same manual-paste rationale as
    acm_certificate_arn — AWS assigns it, gitops/ can't read it, and the
    controller otherwise needs IMDS which the node hop limit blocks).
    Stable unless the VPC is recreated.
  EOT
}

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

output "acm_certificate_arn" {
  value       = module.acm_backend.acm_certificate_arn
  description = <<-EOT
    ARN of the *.abotyan.click wildcard cert. gitops/platform/ingress-nginx
    can't read this at render time (it's pure git, no Terraform access) and
    the AWS Load Balancer Controller doesn't auto-discover certs for plain
    Service-type NLBs (only for ALB Ingress), so this is the one value in
    the whole gitops/ tree that's a manually-pasted literal: after first
    apply, copy this output into
    gitops/platform/ingress-nginx/values-develop.yaml's
    controller.service.annotations."service.beta.kubernetes.io/aws-load-balancer-ssl-cert".
    Stable across applies unless acm.tf's certificate is replaced.
  EOT
}
