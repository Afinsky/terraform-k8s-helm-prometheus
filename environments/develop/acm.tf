module "acm_backend" {
  source  = "terraform-aws-modules/acm/aws"
  version = "v6.3.0"

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
