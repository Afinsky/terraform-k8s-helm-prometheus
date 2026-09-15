variable "environment" {
  description = "Environment"
  type        = string
}

variable "profile" {
  description = "AWS Profile name"
  type        = string
}

variable "region" {
  type        = string
  default     = "us-east-1"
  description = "value of the region where the resources will be created"
}

variable "aws_account_id" {
  type        = string
  description = "Expected AWS account ID (from account.hcl, passed by Terragrunt). Guards provider.tf's allowed_account_ids against an apply landing in the wrong AWS account/profile."
}

variable "repo_root" {
  type        = string
  description = "Absolute path to the repo root, set via Terragrunt's get_repo_root(). Terragrunt always runs Terraform from a copy staged under .terragrunt-cache, so path.module-relative traversal up to files outside this stack (k8s/manifests/, policies/) can't be used — the depth of that staging copy isn't stable."
}

variable "dns_zone_writer_role_arn" {
  type        = string
  description = "ARN of modules/identity-center's dns-zone-writer role, in the management account. external-dns's IRSA role assumes this at runtime to write into the Route53 zone, which lives in that account regardless of which account this module is applied into."
}

variable "dns_zone_name" {
  type        = string
  description = "Domain name of the zone above (external-dns's domainFilters)."
}

# --- Everything below comes from modules/eks-cluster's outputs, via this
# layer's terragrunt.hcl `dependency "eks_cluster"` block - not computed
# here, since the cluster/VPC/ACM cert are a separate Terragrunt state.

variable "cluster_name" {
  type        = string
  description = "EKS cluster name, from modules/eks-cluster's cluster_name output."
}

variable "cluster_endpoint" {
  type        = string
  description = "EKS API server endpoint, from modules/eks-cluster's cluster_endpoint output. Used by the kubernetes/helm providers (provider.tf)."
}

variable "cluster_certificate_authority_data" {
  type        = string
  description = "Base64-encoded cluster CA cert, from modules/eks-cluster's cluster_certificate_authority_data output."
}

variable "oidc_provider" {
  type        = string
  description = "OIDC provider issuer URL (no leading https://), from modules/eks-cluster's oidc_provider output. Used by every IRSA role's trust policy here."
}

variable "oidc_provider_arn" {
  type        = string
  description = "OIDC provider ARN, from modules/eks-cluster's oidc_provider_arn output. Used by every IRSA role's trust policy here."
}

variable "vpc_id" {
  type        = string
  description = "VPC ID, from modules/eks-cluster's vpc_id output. aws-load-balancer-controller needs it to find subnets/security groups."
}

variable "acm_certificate_arn" {
  type        = string
  description = "Validated backend ACM certificate ARN, from modules/eks-cluster's acm_certificate_arn output. Attached to ingress-nginx's Service via annotation."
}
