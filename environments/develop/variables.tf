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
  type        = any
  default     = "us-east-1"
  description = "value of the region where the resources will be created"
}

variable "my_ip_cidr" {
  type        = string
  description = "Your public IP in x.x.x.x/32 format. Restricts the EKS public API endpoint (PLAT-101 lab, Phase 3). Get it with: curl -s https://checkip.amazonaws.com"
}
