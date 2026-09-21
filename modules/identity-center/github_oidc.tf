# GitHub Actions OIDC: lets .github/workflows/plan.yml assume a read-only
# AWS role per PR run without a long-lived access key sitting in a GitHub
# secret - the workflow exchanges its OIDC token for temporary credentials
# each run, same idea as this stack's own use of Identity Center for humans.
#
# tls_certificate fetches GitHub's OIDC endpoint's own TLS chain to derive
# the thumbprint aws_iam_openid_connect_provider requires, instead of
# hardcoding a value that silently goes stale if GitHub ever rotates their
# CA (AWS itself no longer actually validates this thumbprint for
# well-known providers, but the resource still requires the argument).
data "tls_certificate" "github_actions" {
  url = "https://token.actions.githubusercontent.com/.well-known/openid-configuration"
}

resource "aws_iam_openid_connect_provider" "github_actions" {
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.github_actions.certificates[0].sha1_fingerprint]

  tags = local.common_tags
}

# Scoped to this one repo, pull_request-triggered runs only (the "sub"
# claim) - not pushes to main, not other repos even under the same GitHub
# account. This is the ONLY role plan.yml assumes directly; every other
# account's plan (workloads-dev) chains through this one, same shape as
# the "terraform" -> terraform_management -> terraform-target chain
# elsewhere in this stack (see terraform_management.tf,
# account_access_stackset.tf) - just read-only instead of admin.
resource "aws_iam_role" "github_actions_plan" {
  name = "github-actions-plan"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRoleWithWebIdentity"
      Principal = { Federated = aws_iam_openid_connect_provider.github_actions.arn }
      Condition = {
        StringEquals = {
          "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          "token.actions.githubusercontent.com:sub" = "repo:Afinsky/terraform-k8s-helm-prometheus:pull_request"
        }
      }
    }]
  })

  tags = local.common_tags
}

# ReadOnlyAccess, not a hand-scoped policy: `terragrunt plan` across
# 01-identity-center/eks-cluster/eks-workloads touches a wide, evolving set
# of read-only AWS APIs (Organizations, SSO admin, EKS, VPC, ACM, Route53,
# ECR, IAM, CloudFormation...) - narrowing it resource-by-resource would
# need updating on every new resource type this repo ever adds, and a
# read-only call can't mutate anything regardless of how broad the policy
# is. This role can only ever run `plan`, never `apply` - there's no
# credential path from here to anything that writes.
resource "aws_iam_role_policy_attachment" "github_actions_plan" {
  role       = aws_iam_role.github_actions_plan.name
  policy_arn = "arn:aws:iam::aws:policy/ReadOnlyAccess"
}

# root.hcl's S3 backend sets use_lockfile = true (native S3 state locking,
# Terraform >=1.10): even `plan` must PutObject/DeleteObject a
# "<state key>.tflock" object to acquire/release the lock, which
# ReadOnlyAccess alone doesn't grant - every plan.yml job fails at "Error
# acquiring the state lock" without this. Scoped to *.tflock objects only,
# never the .tfstate files themselves, so this role still can't write or
# delete actual state content.
resource "aws_iam_role_policy" "github_actions_plan_state_lock" {
  name = "state-lock"
  role = aws_iam_role.github_actions_plan.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["s3:PutObject", "s3:DeleteObject"]
      Resource = "arn:aws:s3:::dev-me-terraform-state/*.tflock"
    }]
  })
}
