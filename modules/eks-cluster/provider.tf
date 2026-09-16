provider "aws" {
  region                   = var.region
  shared_config_files      = ["$HOME/.aws/config"]
  shared_credentials_files = ["$HOME/.aws/credentials"]
  profile                  = var.profile

  # guard against applying against the wrong AWS account/profile
  allowed_account_ids = [var.aws_account_id]
}

# The Route53 zone this module's ACM validation records go into lives in the
# management account, not this one (see modules/identity-center/dns.tf) — this
# assumes dns-zone-writer from the same base identity as the default provider
# above, exactly like modules/eks-workloads/external-dns.tf's IRSA role does
# at runtime for its own record writes.
provider "aws" {
  alias                    = "dns"
  region                   = var.region
  shared_config_files      = ["$HOME/.aws/config"]
  shared_credentials_files = ["$HOME/.aws/credentials"]
  profile                  = var.profile

  assume_role {
    role_arn = var.dns_zone_writer_role_arn
  }
}

# No kubernetes/helm providers here - this module is pure AWS/VPC/EKS-control-plane
# now (see modules/eks-workloads for everything that talks to the Kubernetes API).
# That split is deliberate: it means `terragrunt destroy` on this layer never
# touches a Service/Ingress/helm_release, so it can't race the AWS Load Balancer
# Controller or external-dns while they're mid-cleanup of their own AWS resources.
