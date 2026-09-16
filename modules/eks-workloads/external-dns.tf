# external-dns
#
# Watches Ingress objects (source=ingress, see external-dns.yaml) and syncs
# their `host:` rules into Route53 as real DNS records - see
# DNS_MANAGEMENT_TODO.md for why this is needed (nothing else in this repo
# creates records for hosts declared in app.yaml's Ingress) and why this
# option (vs. a manual aws_route53_record or a wildcard record) was picked.
#
# Same IRSA pattern as load-balancer-controller.tf: dedicated role trusting only this controller's
# ServiceAccount. Its own permissions are just an assume-role, though - the
# Route53 zone lives in the management account (modules/identity-center/dns.tf),
# not this one, so this role hops through dns-zone-writer there rather than
# calling Route53 directly. See aws_iam_role_policy.external_dns_assume_dns.

resource "aws_iam_role" "external_dns" {
  name               = "${local.prefix}-external-dns"
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
          "${var.oidc_provider}:sub": "system:serviceaccount:external-dns:external-dns",
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

# The official tutorial (https://github.com/kubernetes-sigs/external-dns/blob/master/docs/tutorials/aws.md)
# grants route53:* directly here; this repo's zone isn't in this account, so
# instead the only permission this role needs is to assume dns-zone-writer
# (modules/identity-center/dns.tf), which holds the actual Route53 permissions,
# scoped to the one zone, over there.
resource "aws_iam_role_policy" "external_dns_assume_dns" {
  name = "${local.prefix}-external-dns-assume-dns"
  role = aws_iam_role.external_dns.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "sts:AssumeRole"
      Resource = [var.dns_zone_writer_role_arn]
    }]
  })
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
      value = var.cluster_name
    },
    {
      # Flag name verified live via `external-dns --help` against app
      # version v0.21.0 (pinned above) - it's "--aws-assume-role", not
      # "--aws-assume-role-arn" (the upstream AWS tutorial's name, which
      # this CLI doesn't actually accept and fails to start with
      # "unknown long flag '--aws-assume-role-arn'"). Re-verify the same
      # way if a future chart bump ever breaks Route53 auth.
      name  = "extraArgs.aws-assume-role"
      value = var.dns_zone_writer_role_arn
      type  = "string"
    }
  ]

  set_list = [
    {
      name  = "domainFilters"
      value = [var.dns_zone_name]
    }
  ]

  # Reconciliation-order reasoning, same as helm_release.ingress_nginx in
  # ingress-nginx.tf: ingress-nginx's Service needs to exist so its controller can
  # start publishing LB status onto each Ingress (which external-dns then
  # reads), and its IAM role needs to be assumable before it can call
  # Route53 at all.
  #
  # Destroy-time note: unlike ingress-nginx/lb-controller, there's no
  # finalizer-based mechanism forcing Terraform to wait for external-dns to
  # actually remove a Route53 record before this release is considered
  # destroyed - it just runs on its own poll interval (default ~1 min).
  # A record can outlive the destroy by a few minutes; harmless (Route53
  # records don't block VPC/subnet teardown the way orphaned ALB/NLB ENIs
  # do), and `policy: sync` cleans it up on the next apply regardless.
  depends_on = [helm_release.ingress_nginx, aws_iam_role_policy.external_dns_assume_dns]
}
