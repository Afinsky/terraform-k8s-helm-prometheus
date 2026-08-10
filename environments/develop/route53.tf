data "aws_route53_zone" "zone" {
  name         = local.zone_name
  private_zone = false
}

locals {
  #zone_id   = module.zones.route53_zone_zone_id[local.zone_name]
  zone_id   = data.aws_route53_zone.zone.zone_id
  zone_name = "abotyan.click"
}
# How to create DNS record for load balancer in route53 using k8s

# # module "zones" {
# #   source = "github.com/terraform-aws-modules/terraform-aws-route53//modules/zones?ref=v5.0.0"
# #
# #   zones = {
# #     "${local.zone_name}" = {
# #       name    = local.zone_name
# #       comment = "Primary zone for ${local.resource_name}-${var.environment}"
# #       tags = {
# #         Name = "${local.resource_name}-${var.environment}-zone"
# #       }
# #     }
# #   }
# # }
#
# module "records" {
#   source = "github.com/terraform-aws-modules/terraform-aws-route53//modules/records?ref=v5.0.0"
#
#   zone_id = local.zone_id
#   records = [
#     {
#       name            = trimsuffix(local.validation_domain_resource_record_name, ".${local.zone_name}")
#       type            = "CNAME"
#       allow_overwrite = true
#       ttl             = 3600
#       records         = [local.validation_domain_resource_record_value]
#     }
#   ]
# }
