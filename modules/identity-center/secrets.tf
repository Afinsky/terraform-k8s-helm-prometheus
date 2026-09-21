# Cross-account secrets reader: app secrets (e.g. photoapp's DB credentials,
# read by modules/eks-workloads/external-secrets.tf) live centrally in
# Secrets Manager here, in the management account, rather than duplicated
# per workload account - same reasoning as dns.tf's Route53 zone: one home
# for the data, not one copy per account. Secrets Manager has no
# resource-based policy either, so the only way for external-secrets in a
# target account to read a secret here is to assume a role defined here.
#
# Trusted the same way dns_zone_writer is: any account's external-secrets
# IRSA role (`*-external-secrets`), matched by ARN pattern rather than
# per-account, so a new target account needs no change here.
resource "aws_iam_role" "secrets_reader" {
  name = "secrets-reader"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { AWS = "*" }
      Action    = "sts:AssumeRole"
      Condition = {
        StringEquals = {
          "aws:PrincipalOrgID" = aws_organizations_organization.this.id
        }
        StringLike = {
          "aws:PrincipalArn" = [
            "arn:aws:iam::*:role/*-external-secrets",
          ]
        }
      }
    }]
  })

  tags = local.common_tags
}

locals {
  # Every account's modules/eks-workloads applies with the same
  # project_name/environment/region (see that module's locals.tf -
  # duplicated there rather than shared, same reasoning as this
  # duplication), so this one prefix covers every account's app secrets
  # without a per-account entry. Update both places together if that
  # formula ever changes.
  workload_secrets_prefix = "me-dev-us-east-1"
}

# Same shape as modules/eks-workloads/external-secrets.tf's old (now
# removed) same-account policy: least privilege by naming convention, no
# account-wide ListSecrets.
resource "aws_iam_role_policy" "secrets_reader" {
  name = "secrets-reader"
  role = aws_iam_role.secrets_reader.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "secretsmanager:GetSecretValue",
        "secretsmanager:DescribeSecret",
      ]
      Resource = [
        "arn:aws:secretsmanager:${var.region}:${var.aws_account_id}:secret:${local.workload_secrets_prefix}/*"
      ]
    }]
  })
}

# Declares the *existence* of every app secret this Organization's
# workloads expect to find at read time - not their value (see the
# deliberately-omitted secret_string below). Before this resource, a
# renamed or deleted secret was invisible to `terraform plan`; the first
# sign was external-secrets' `CreateContainerConfigError` at pod-start
# time in the cluster, not a plan diff - this is that gap closed for
# photoapp's secret specifically (the only ExternalSecret consumer today -
# see k8s/manifests/app.yaml). Add one entry per new app secret as it's
# introduced.
resource "aws_secretsmanager_secret" "photoapp_db_credentials" {
  name        = "${local.workload_secrets_prefix}/photoapp/db-credentials"
  description = "photoapp's DB username/password (modules/eks-workloads' ExternalSecret, k8s/manifests/app.yaml). Value is set by hand (aws secretsmanager put-secret-value / console) - deliberately not a `secret_string` argument here, so plaintext credentials never enter this repo's Terraform state or history."

  tags = local.common_tags
}
