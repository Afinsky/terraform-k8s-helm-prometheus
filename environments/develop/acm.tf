# resource "aws_acm_certificate" "backend" {
#   domain_name = "abotyan.net"
#   subject_alternative_names = [
#     "*.abotyan.net"
#   ]
#   validation_method = "DNS"
#
#   tags = {
#     Name = "${local.resource_name}-${var.environment}-backend-validation"
#   }
#
#   lifecycle {
#     create_before_destroy = true
#   }
# }
#
# # Create a DNS validation record in the Route53 zone for each domain on the cert.
# # The apex and the wildcard produce the same CNAME, so keying by domain_name
# # de-duplicates them and avoids a "duplicate record" error.
# resource "aws_route53_record" "backend_validation" {
#   for_each = {
#     for dvo in aws_acm_certificate.backend.domain_validation_options : dvo.domain_name => {
#       name   = dvo.resource_record_name
#       record = dvo.resource_record_value
#       type   = dvo.resource_record_type
#     }
#   }
#
#   zone_id         = local.zone_id
#   name            = each.value.name
#   type            = each.value.type
#   records         = [each.value.record]
#   ttl             = 60
#   allow_overwrite = true
# }
#
# # # Waits until ACM sees the DNS records and marks the certificate as ISSUED.
# # resource "aws_acm_certificate_validation" "backend" {
# #   certificate_arn         = aws_acm_certificate.backend.arn
# #   validation_record_fqdns = [for record in aws_route53_record.backend_validation : record.fqdn]
# # }
#
# output "validation_record_fqdns" {
#   value = [for record in aws_route53_record.backend_validation : record.fqdn]
# }
#

module "acm_backend" {
  source  = "terraform-aws-modules/acm/aws"
  version = "4.0.1"

  domain_name = local.zone_name
  subject_alternative_names = [
    "*.${local.zone_name}"
  ]

  zone_id             = local.zone_id
  validation_method   = "DNS"
  wait_for_validation = false #true

  tags = {
    Name = "${local.resource_name}-${var.environment}-backend-validation"
  }
}

# output "validation_route53_record_fqdns" {
#   value = module.acm_backend.validation_route53_record_fqdns
# }
#
# output "validation_domains_resource_record_name" {
#   value = one(module.acm_backend.validation_domains[*]["resource_record_name"])
# }
#
# output "validation_domains_resource_record_value" {
#   value = one(module.acm_backend.validation_domains[*]["resource_record_value"])
# }

# locals {
#   validation_domain_resource_record_name  = one(module.acm_backend.validation_domains[*]["resource_record_name"])
#   validation_domain_resource_record_value = one(module.acm_backend.validation_domains[*]["resource_record_value"])
# }
