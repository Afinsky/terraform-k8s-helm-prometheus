#-------------------------------------------------------------
# global.hcl
#
# - set global variables
# - root.hcl in the repo root consolidates this file
#-------------------------------------------------------------

locals {
  project_name = "me"

  common_tags = {
    client    = "K8S practice"
    project   = "K8S"
    owner     = "me"
    terraform = "true"
  }

  # modules/develop's Route53 zone, and the role it assumes to write into it
  # cross-account — both live in the management account (abotyan001), not
  # wherever modules/develop itself gets applied. One zone/role for the
  # whole Organization, so these are global rather than per-account/layer
  # inputs. Source of truth: accounts/abotyan001/us-east-1/01-identity-center's
  # dns_zone_writer_role_arn/dns_zone_id/dns_zone_name outputs — update these
  # by hand if that stack is ever re-applied with a different zone/role.
  dns_zone_writer_role_arn = "arn:aws:iam::417886991962:role/dns-zone-writer"
  dns_zone_id              = "Z03682881TYQWE74HYLWJ"
  dns_zone_name            = "abotyan.click"
}
