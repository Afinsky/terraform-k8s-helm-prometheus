variable "environment" {
  description = "Environment"
  type        = string
}

variable "profile" {
  description = "AWS Profile name. Before the first apply the lab-admin SSO profile doesn't exist yet — chicken and egg. Use the same profile you're currently actually working under (e.g. the same \"terraform\" as in environments/develop)."
  type        = string
}

variable "region" {
  type        = string
  default     = "us-east-1"
  description = "Region. IAM Identity Center lives in a single region — pick the same one the lab cluster will run in."
}

variable "email" {
  type        = string
  default     = "a.afinsky@gmail.com"
  description = "Your mailbox. aliaksei/alice/bob use aliases like you+admin@gmail.com — all mail lands in this same inbox."
}
