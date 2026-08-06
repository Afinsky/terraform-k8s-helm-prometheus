module "acm_backend" {
  source  = "terraform-aws-modules/acm/aws"
  version = "4.0.1"

  domain_name = "abotyan.net"
  subject_alternative_names = [
    "*.abotyan.net"
  ]

  zone_id             = local.zone_id
  validation_method   = "DNS"
  wait_for_validation = true

  tags = {
    Name = "${local.resource_name}-${var.environment}-backend-validation"
  }
}
