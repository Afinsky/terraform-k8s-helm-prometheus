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
}
