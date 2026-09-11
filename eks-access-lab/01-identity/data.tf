data "aws_caller_identity" "current" {}

# ------------------------------------------------------------------
# Between apply #1 (organization.tf) and apply #2 (this data source)
# a manual step is required: enable IAM Identity Center in the console.
# The AWS provider has no resource that enables Identity Center as an
# organization instance, so this data source would otherwise find nothing.
# See README.md.
# ------------------------------------------------------------------
data "aws_ssoadmin_instances" "this" {}
