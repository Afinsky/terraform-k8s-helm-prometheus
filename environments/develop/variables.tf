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

# variable "domain_registrant_contact" {
#   description = "WHOIS contact used for admin/registrant/tech on aws_route53domains_domain. Supply via secure_variables.tfvars (gitignored) — never commit real contact details."
#   type = object({
#     first_name        = string
#     last_name         = string
#     organization_name = optional(string)
#     contact_type       = optional(string, "PERSON")
#     address_line_1     = string
#     address_line_2     = optional(string)
#     city               = string
#     state              = optional(string)
#     zip_code           = string
#     country_code       = string
#     email              = string
#     phone_number       = string
#   })
#   sensitive = true
#   default   = null
# }
