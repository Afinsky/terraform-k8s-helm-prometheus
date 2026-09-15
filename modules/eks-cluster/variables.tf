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

variable "dns_zone_writer_role_arn" {
  type        = string
  description = "ARN of modules/identity-center's dns-zone-writer role, in the management account. Assumed by the aws.dns provider (see provider.tf) for this module's own ACM validation records - the Route53 zone lives in that account regardless of which account this module is applied into."
}

variable "dns_zone_id" {
  type        = string
  description = "Route53 hosted zone ID, from 01-identity-center's dns_zone_id output. The zone itself lives in the management account, not this one."
}

variable "dns_zone_name" {
  type        = string
  description = "Domain name of the zone above, from 01-identity-center's dns_zone_name output."
}
