# # Registers local.zone_name via Route53 Domains and points it at the NS
# # records of the hosted zone already created in route53.tf, so it never
# # ends up delegated to a second, duplicate zone.
# #
# # Disabled unless domain_registrant_contact is supplied (real purchase,
# # real WHOIS contact) — see secure_variables.tfvars.example.
# resource "aws_route53domains_domain" "lab" {
#   count = var.domain_registrant_contact != null ? 1 : 0
#
#   domain_name       = local.zone_name
#   duration_in_years = 1
#   auto_renew        = false
#   transfer_lock     = true
#
#   admin_privacy      = true
#   registrant_privacy = true
#   tech_privacy       = true
#   billing_privacy    = true
#
#   dynamic "name_server" {
#     for_each = module.zones.route53_zone_name_servers[local.zone_name]
#     content {
#       name = name_server.value
#     }
#   }
#
#   admin_contact {
#     first_name         = var.domain_registrant_contact.first_name
#     last_name          = var.domain_registrant_contact.last_name
#     organization_name  = var.domain_registrant_contact.organization_name
#     contact_type       = var.domain_registrant_contact.contact_type
#     address_line_1     = var.domain_registrant_contact.address_line_1
#     address_line_2     = var.domain_registrant_contact.address_line_2
#     city               = var.domain_registrant_contact.city
#     state              = var.domain_registrant_contact.state
#     zip_code           = var.domain_registrant_contact.zip_code
#     country_code       = var.domain_registrant_contact.country_code
#     email              = var.domain_registrant_contact.email
#     phone_number       = var.domain_registrant_contact.phone_number
#   }
#
#   registrant_contact {
#     first_name         = var.domain_registrant_contact.first_name
#     last_name          = var.domain_registrant_contact.last_name
#     organization_name  = var.domain_registrant_contact.organization_name
#     contact_type       = var.domain_registrant_contact.contact_type
#     address_line_1     = var.domain_registrant_contact.address_line_1
#     address_line_2     = var.domain_registrant_contact.address_line_2
#     city               = var.domain_registrant_contact.city
#     state              = var.domain_registrant_contact.state
#     zip_code           = var.domain_registrant_contact.zip_code
#     country_code       = var.domain_registrant_contact.country_code
#     email              = var.domain_registrant_contact.email
#     phone_number       = var.domain_registrant_contact.phone_number
#   }
#
#   tech_contact {
#     first_name         = var.domain_registrant_contact.first_name
#     last_name          = var.domain_registrant_contact.last_name
#     organization_name  = var.domain_registrant_contact.organization_name
#     contact_type       = var.domain_registrant_contact.contact_type
#     address_line_1     = var.domain_registrant_contact.address_line_1
#     address_line_2     = var.domain_registrant_contact.address_line_2
#     city               = var.domain_registrant_contact.city
#     state              = var.domain_registrant_contact.state
#     zip_code           = var.domain_registrant_contact.zip_code
#     country_code       = var.domain_registrant_contact.country_code
#     email              = var.domain_registrant_contact.email
#     phone_number       = var.domain_registrant_contact.phone_number
#   }
#
#   billing_contact {
#     first_name         = var.domain_registrant_contact.first_name
#     last_name          = var.domain_registrant_contact.last_name
#     organization_name  = var.domain_registrant_contact.organization_name
#     contact_type       = var.domain_registrant_contact.contact_type
#     address_line_1     = var.domain_registrant_contact.address_line_1
#     address_line_2     = var.domain_registrant_contact.address_line_2
#     city               = var.domain_registrant_contact.city
#     state              = var.domain_registrant_contact.state
#     zip_code           = var.domain_registrant_contact.zip_code
#     country_code       = var.domain_registrant_contact.country_code
#     email              = var.domain_registrant_contact.email
#     phone_number       = var.domain_registrant_contact.phone_number
#   }
# }
