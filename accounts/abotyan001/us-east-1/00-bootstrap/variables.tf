variable "profile" {
  description = "AWS Profile name"
  type        = string
}

variable "environment" {
  description = "Environment"
  type        = string
}

variable "aws_account_id" {
  type        = string
  description = "Expected AWS account ID (from accounts/abotyan001/account.hcl, passed by Terragrunt). Guards main.tf's allowed_account_ids against an apply landing in the wrong AWS account/profile."
}
