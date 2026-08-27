# external-dns
#
# Watches Ingress objects (source=ingress, see external-dns.yaml) and syncs
# their `host:` rules into Route53 as real DNS records - see
# DNS_MANAGEMENT_TODO.md for why this is needed (nothing else in this repo
# creates records for hosts declared in app.yaml's Ingress) and why this
# option (vs. a manual aws_route53_record or a wildcard record) was picked.
#
# Same IRSA pattern as load-balancer-controller.tf: dedicated role trusting only this controller's
# ServiceAccount, permissions scoped to the one zone this repo manages
# (route53.tf) rather than the account-wide `hostedzone/*` the upstream
# tutorial defaults to - see the comment on aws_iam_policy.external_dns.

resource "aws_iam_role" "external_dns" {
  name               = "${local.prefix}-external-dns"
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
          "${module.eks.oidc_provider}:sub": "system:serviceaccount:external-dns:external-dns",
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

# Same permission set as the official tutorial
# (https://github.com/kubernetes-sigs/external-dns/blob/master/docs/tutorials/aws.md),
# tightened per that same doc's own least-privilege suggestion: the mutating
# actions are scoped to the one zone in route53.tf (local.zone_id) instead of
# every hosted zone in the account. ListHostedZones has to stay on "*" -
# Route53 doesn't support resource-level permissions for that call.
resource "aws_iam_policy" "external_dns" {
  name = "${local.prefix}-external-dns"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "route53:ChangeResourceRecordSets",
          "route53:ListResourceRecordSets",
          "route53:ListTagsForResources",
        ]
        Resource = ["arn:aws:route53:::hostedzone/${local.zone_id}"]
      },
      {
        Effect   = "Allow"
        Action   = ["route53:ListHostedZones"]
        Resource = ["*"]
      },
    ]
  })
}

resource "aws_iam_role_policy_attachment" "external_dns" {
  role       = aws_iam_role.external_dns.name
  policy_arn = aws_iam_policy.external_dns.arn
}

# The Helm release moved to ArgoCD (gitops/platform/external-dns/). Terraform
# creates the namespace + ServiceAccount ahead of time (the chart deploys
# with serviceAccount.create=false) so the IRSA annotation never has to
# round-trip through a Helm `set` value. txtOwnerId (= cluster name) and
# domainFilters (= local.zone_name) are plain literals in
# gitops/platform/external-dns/values-develop.yaml instead - both are
# deterministic from develop.tfvars/locals.tf, not discovered at apply time.
resource "kubernetes_namespace_v1" "external_dns" {
  metadata {
    name = "external-dns"
  }

  depends_on = [module.eks]
}

resource "kubernetes_service_account_v1" "external_dns" {
  metadata {
    name      = "external-dns"
    namespace = kubernetes_namespace_v1.external_dns.metadata[0].name
    annotations = {
      "eks.amazonaws.com/role-arn" = aws_iam_role.external_dns.arn
    }
  }

  depends_on = [aws_iam_role_policy_attachment.external_dns]
}
