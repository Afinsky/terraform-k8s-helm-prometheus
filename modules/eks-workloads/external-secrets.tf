# External Secrets Operator (ESO)
#
# Syncs secrets from AWS Secrets Manager into native Kubernetes Secret
# objects via ExternalSecret resources that apps reference like any other
# Secret. Same IRSA pattern as external-dns.tf / load-balancer-controller.tf:
# a dedicated role trusting only this controller's ServiceAccount.
#
# App secrets live centrally in Secrets Manager in the management account,
# not per-account (same reasoning as the Route53 zone in dns.tf) - so, same
# as external-dns.tf, this role's own permissions are just an assume-role:
# it hops through modules/identity-center's secrets-reader role
# (modules/identity-center/secrets.tf), which holds the actual
# GetSecretValue/DescribeSecret permissions, scoped by naming prefix, over
# there. See aws_iam_role_policy.external_secrets_assume_secrets.

resource "aws_iam_role" "external_secrets" {
  name               = "${local.prefix}-external-secrets"
  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "${var.oidc_provider_arn}"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "${var.oidc_provider}:sub": "system:serviceaccount:external-secrets:external-secrets",
          "${var.oidc_provider}:aud": "sts.amazonaws.com"
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

resource "aws_iam_role_policy" "external_secrets_assume_secrets" {
  name = "${local.prefix}-external-secrets-assume-secrets"
  role = aws_iam_role.external_secrets.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "sts:AssumeRole"
      Resource = [var.secrets_reader_role_arn]
    }]
  })
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

  values = [file("${var.repo_root}/k8s/helm/external-secrets.yaml")]

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
  depends_on = [aws_iam_role_policy.external_secrets_assume_secrets, helm_release.aws_load_balancer_controller]
}

# ClusterSecretStore, applied the same way app.tf applies app.yaml: decode
# raw YAML from k8s/manifests/ rather than hand-writing a kubernetes_manifest
# block. Cluster-scoped (vs. namespaced SecretStore) so any namespace's
# ExternalSecret can reference it by name.
locals {
  external_secrets_manifest = provider::kubernetes::manifest_decode_multi(
    templatefile("${var.repo_root}/k8s/manifests/external-secrets.yaml", {
      region   = var.region
      role_arn = var.secrets_reader_role_arn
    })
  )
}

resource "kubernetes_manifest" "external_secrets_cluster_store" {
  count    = length(local.external_secrets_manifest)
  manifest = local.external_secrets_manifest[count.index]

  # The ClusterSecretStore CRD only exists once the chart's CRDs are
  # installed, and the ServiceAccount it references (external-secrets) must
  # already exist with its IRSA annotation.
  depends_on = [helm_release.external_secrets]
}
