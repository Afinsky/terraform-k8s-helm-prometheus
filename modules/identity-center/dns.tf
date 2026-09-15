# Cross-account DNS writer: modules/eks-cluster runs in target accounts (workloads-dev
# and future ones), but the Route53 zone stays here in the management account —
# nothing else in this Organization moves it, and it's simplest for a
# personal-domain zone to have exactly one home. Route53 hosted zones have no
# resource-based policy, so the only way for something in a target account to
# write records into this zone is to assume a role defined here.
#
# Two distinct callers assume this role, both by ARN pattern (not per-account,
# so a new target account needs no change here):
#   - external-dns's IRSA role in each target cluster (`*-external-dns`,
#     see modules/eks-cluster/external-dns.tf) - the live controller, syncing
#     Ingress hosts into Route53 on an ongoing basis.
#   - the SSO `devops-admin` role - modules/eks-cluster's ACM setup creates the
#     one-time DNS validation CNAME record for each cluster's certificate as
#     that same identity (the one `terragrunt apply` runs as for `eks-cluster`).
data "aws_route53_zone" "this" {
  name         = local.zone_name
  private_zone = false
}

locals {
  zone_name = "abotyan.click"
}

resource "aws_iam_role" "dns_zone_writer" {
  name = "dns-zone-writer"

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
            "arn:aws:iam::*:role/*-external-dns",
            "arn:aws:iam::*:role/aws-reserved/sso.amazonaws.com/AWSReservedSSO_devops-admin_*",
          ]
        }
      }
    }]
  })

  tags = local.common_tags
}

# Same shape as modules/eks-cluster/external-dns.tf's own policy (that role's
# permissions collapse to just this assume, once it stops touching Route53
# directly - see that file): mutating actions scoped to the one zone,
# ListHostedZones on "*" since Route53 has no resource-level permissions for it.
resource "aws_iam_role_policy" "dns_zone_writer" {
  name = "dns-zone-writer"
  role = aws_iam_role.dns_zone_writer.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "route53:ChangeResourceRecordSets",
          "route53:ListResourceRecordSets",
          "route53:ListTagsForResources",
          # aws_route53_record (used by modules/eks-cluster's ACM DNS
          # validation) reads the zone before writing to it - missed this the
          # first time around, surfaced as an AccessDenied on GetHostedZone.
          "route53:GetHostedZone",
        ]
        Resource = ["arn:aws:route53:::hostedzone/${data.aws_route53_zone.this.zone_id}"]
      },
      {
        Effect   = "Allow"
        Action   = ["route53:ListHostedZones"]
        Resource = ["*"]
      },
    ]
  })
}
