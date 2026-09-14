# The certificate itself is issued in this (target) account — ACM certs can
# only be attached to a load balancer in the same account, so it can't live
# in the management account instead. Its DNS validation CNAME, though, has
# to go into the Route53 zone, which does live in the management account
# (modules/identity-center/dns.tf) — hence the split into two module calls below
# instead of the module's usual single call.
module "acm_backend" {
  source  = "terraform-aws-modules/acm/aws"
  version = "v6.3.0"

  domain_name = local.zone_name
  subject_alternative_names = [
    "*.${local.zone_name}"
  ]

  validation_method = "DNS"

  # No Route53 access from here — the aws.dns-provider call below creates
  # the validation record, and aws_acm_certificate_validation below waits
  # on it explicitly.
  create_route53_records = false
  validate_certificate   = false

  tags = {
    Name = "${local.resource_name}-${var.environment}-backend-validation"
  }
}

# Same module, second instance: creates only the Route53 validation
# record(s) named above, via the aws.dns provider (assumes dns-zone-writer
# in the management account — see provider.tf).
module "acm_backend_dns_validation" {
  source  = "terraform-aws-modules/acm/aws"
  version = "v6.3.0"

  providers = {
    aws = aws.dns
  }

  create_certificate          = false
  create_route53_records_only = true
  validation_method           = "DNS"

  zone_id                                   = local.zone_id
  acm_certificate_domain_validation_options = module.acm_backend.acm_certificate_domain_validation_options
  distinct_domain_names                     = module.acm_backend.distinct_domain_names
}

resource "aws_acm_certificate_validation" "backend" {
  certificate_arn         = module.acm_backend.acm_certificate_arn
  validation_record_fqdns = module.acm_backend_dns_validation.validation_route53_record_fqdns
}
