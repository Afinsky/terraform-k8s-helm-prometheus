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

  # dns_zone_writer_role_arn/dns_zone_id/dns_zone_name/secrets_reader_role_arn
  # used to live here as hardcoded literals ("update by hand if
  # identity-center is ever re-applied with a different zone/role") -
  # every eks-cluster/eks-workloads terragrunt.hcl now reads them live via a
  # `dependency "identity_center"` block instead (see any of those files'
  # comment for why), so they're not needed globally anymore.
}
