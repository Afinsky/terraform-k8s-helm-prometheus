locals {
  zone_id = module.zones.route53_zone_zone_id["abotyan.net"]
}

module "zones" {
  source = "github.com/terraform-aws-modules/terraform-aws-route53//modules/zones?ref=v2.10.2"

  zones = {
    "abotyan.net" = {
      name    = "abotyan.net"
      comment = "Primary zone for ${local.resource_name}-${var.environment}"
      tags = {
        Name = "${local.resource_name}-${var.environment}-zone"
      }
    }
  }
}
