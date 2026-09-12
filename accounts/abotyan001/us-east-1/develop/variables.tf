variable "environment" {
  description = "Environment"
  type        = string
}

variable "profile" {
  description = "AWS Profile name"
  type        = string
}

variable "enable_flow_log" {
  description = "Whether or not to enable VPC Flow Logs"
  type        = bool
  default     = false
}

variable "vpc" {
  description = "VPC configuration keyed by network name"
  type        = any
  default     = null
}

variable "region" {
  type        = string
  default     = "us-east-1"
  description = "value of the region where the resources will be created"
}

variable "my_ip_cidr" {
  type        = string
  description = "Your public IP in x.x.x.x/32 format. Restricts the EKS public API endpoint (PLAT-101 lab, Phase 3). Get it with: curl -s https://checkip.amazonaws.com"
}

variable "aws_account_id" {
  type        = string
  description = "Expected AWS account ID (from accounts/abotyan001/account.hcl, passed by Terragrunt). Guards provider.tf's allowed_account_ids against an apply landing in the wrong AWS account/profile."
}

variable "repo_root" {
  type        = string
  description = "Absolute path to the repo root, set via Terragrunt's get_repo_root(). Terragrunt always runs Terraform from a copy staged under .terragrunt-cache, so path.module-relative traversal up to files outside this stack (k8s/manifests/, policies/) can't be used — the depth of that staging copy isn't stable."
}
