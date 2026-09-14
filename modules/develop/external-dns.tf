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

resource "helm_release" "external_dns" {
  name             = "external-dns"
  repository       = "https://kubernetes-sigs.github.io/external-dns/"
  chart            = "external-dns"
  namespace        = "external-dns"
  create_namespace = true
  version          = "1.21.1" # controller app version v0.21.0.
  # Verified live via `helm search repo external-dns/external-dns --versions`
  # on 2026-08-13. Re-run that search before every future version bump.

  values = [file("${var.repo_root}/k8s/helm/external-dns.yaml")]

  set = [
    {
      name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
      value = aws_iam_role.external_dns.arn
      type  = "string"
    },
    {
      name  = "txtOwnerId"
      value = module.eks.cluster_name
    }
  ]

  set_list = [
    {
      name  = "domainFilters"
      value = [local.zone_name]
    }
  ]

  # Reconciliation-order reasoning, same as helm_release.ingress_nginx in
  # ingress-nginx.tf: ingress-nginx's Service needs to exist so its controller can
  # start publishing LB status onto each Ingress (which external-dns then
  # reads), and its IAM role needs to be assumable before it can call
  # Route53 at all.
  depends_on = [module.eks, helm_release.ingress_nginx, aws_iam_role_policy_attachment.external_dns]
}
