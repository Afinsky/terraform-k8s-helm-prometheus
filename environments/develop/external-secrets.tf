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

resource "helm_release" "external_secrets" {
  name             = "external-secrets"
  repository       = "https://charts.external-secrets.io"
  chart            = "external-secrets"
  namespace        = "external-secrets"
  create_namespace = true
  version          = "2.9.0" # controller app version v2.9.0.
  # Verified live via `helm search repo external-secrets/external-secrets --versions`
  # on 2026-08-16. Re-run that search before every future version bump.

  values = [file("./../../k8s/helm/external-secrets.yaml")]

  set = [
    {
      name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
      value = aws_iam_role.external_secrets.arn
      type  = "string"
    }
  ]

  # Same access-entry ordering constraint as the other helm_release
  # resources: the helm provider needs to reach the API server as an admin
  # principal, and the IRSA role needs to be assumable once pods start.
  # Also needs the LB Controller's webhook pod up first: it registers a
  # cluster-wide mutating webhook on Service objects, and this chart creates
  # its own webhook Service - without this dependency the create can race
  # ahead and hit "no endpoints available" on that webhook.
  depends_on = [module.eks, aws_iam_role_policy_attachment.external_secrets, helm_release.aws_load_balancer_controller]
}

# # ClusterSecretStore, applied the same way app.tf applies app.yaml: decode
# # raw YAML from k8s/manifests/ rather than hand-writing a kubernetes_manifest
# # block. Cluster-scoped (vs. namespaced SecretStore) so any namespace's
# # ExternalSecret can reference it by name.
# locals {
#   external_secrets_manifest = provider::kubernetes::manifest_decode_multi(
#     templatefile("${path.module}/../../k8s/manifests/external-secrets.yaml", {
#       region = var.region
#     })
#   )
# }
#
# resource "kubernetes_manifest" "external_secrets_cluster_store" {
#   count    = length(local.external_secrets_manifest)
#   manifest = local.external_secrets_manifest[count.index]
#
#   # The ClusterSecretStore CRD only exists once the chart's CRDs are
#   # installed, and the ServiceAccount it references (external-secrets) must
#   # already exist with its IRSA annotation.
#   depends_on = [module.eks, helm_release.external_secrets]
# }
