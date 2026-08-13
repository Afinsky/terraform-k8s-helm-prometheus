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
