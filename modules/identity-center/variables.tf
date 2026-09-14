variable "environment" {
  description = "Environment"
  type        = string
}

variable "profile" {
  description = "AWS Profile name. Always \"terraform\" (static IAM user) for this stack — it defines the lab-admin SSO role itself, so it can't safely run under it. See provider.tf."
  type        = string
}

variable "region" {
  type        = string
  default     = "us-east-1"
  description = "Region. IAM Identity Center lives in a single region — pick the same one the lab cluster will run in."
}

variable "aws_account_id" {
  type        = string
  description = "Expected AWS account ID (from accounts/abotyan001/account.hcl, passed by Terragrunt). Guards provider.tf's allowed_account_ids against an apply landing in the wrong AWS account/profile."
}

variable "email" {
  type        = string
  default     = "a.afinsky@gmail.com"
  description = "Your mailbox. aliaksei/alice/bob use aliases like you+admin@gmail.com — all mail lands in this same inbox."
}
