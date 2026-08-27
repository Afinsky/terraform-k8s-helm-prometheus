# External Secrets Operator (ESO)
#
# Syncs secrets from AWS Secrets Manager into native Kubernetes Secret
# objects via ExternalSecret resources that apps reference like any other
# Secret. Same IRSA pattern as external-dns.tf / load-balancer-controller.tf:
# a dedicated role trusting only this controller's ServiceAccount, policy
# scoped to a naming prefix rather than every secret in the account.
#
# Least privilege is enforced by naming convention: only secrets named
# "${local.prefix}/*" (e.g. "me-dev-us-east-1/my-app/db-password") are
# readable. Name new secrets under that prefix, or widen
# aws_iam_policy.external_secrets below if a different scheme is needed.
# ListSecrets is intentionally omitted - ExternalSecrets in this repo
# reference keys directly (dataFrom.find, which needs account-wide
# ListSecrets, is not supported by this policy).

resource "aws_iam_role" "external_secrets" {
  name               = "${local.prefix}-external-secrets"
  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "${module.eks.oidc_provider_arn}"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "${module.eks.oidc_provider}:sub": "system:serviceaccount:external-secrets:external-secrets",
          "${module.eks.oidc_provider}:aud": "sts.amazonaws.com"
        }
      }
    }
  ]
}
EOF

  tags = {
    environment = var.environment
    managed_by  = "terraform"
    project     = local.project_name
  }
}

resource "aws_iam_policy" "external_secrets" {
  name = "${local.prefix}-external-secrets"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret",
        ]
        Resource = [
          "arn:aws:secretsmanager:${var.region}:${data.aws_caller_identity.current.account_id}:secret:${local.prefix}/*"
        ]
      },
    ]
  })
}

resource "aws_iam_role_policy_attachment" "external_secrets" {
  role       = aws_iam_role.external_secrets.name
  policy_arn = aws_iam_policy.external_secrets.arn
}

# The Helm release + ClusterSecretStore moved to ArgoCD
# (gitops/platform/external-secrets/) — the ClusterSecretStore manifest lives
# at gitops/platform/external-secrets/manifests/cluster-secret-store.yaml
# now, applied by the same Application as the chart via sync-wave ordering
# (chart's CRDs and ServiceAccount first, ClusterSecretStore after). Terraform
# creates the namespace + ServiceAccount ahead of time (the chart deploys
# with serviceAccount.create=false) so the IRSA annotation never has to
# round-trip through a Helm `set` value.
resource "kubernetes_namespace_v1" "external_secrets" {
  metadata {
    name = "external-secrets"
  }

  depends_on = [module.eks]
}

resource "kubernetes_service_account_v1" "external_secrets" {
  metadata {
    name      = "external-secrets"
    namespace = kubernetes_namespace_v1.external_secrets.metadata[0].name
    annotations = {
      "eks.amazonaws.com/role-arn" = aws_iam_role.external_secrets.arn
    }
  }

  depends_on = [aws_iam_role_policy_attachment.external_secrets]
}
