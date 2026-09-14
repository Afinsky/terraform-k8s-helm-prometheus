provider "aws" {
  region                   = var.region
  shared_config_files      = ["$HOME/.aws/config"]
  shared_credentials_files = ["$HOME/.aws/credentials"]
  profile                  = var.profile

  # guard against applying against the wrong AWS account/profile
  allowed_account_ids = [var.aws_account_id]
}

# The Route53 zone this module's ACM validation records go into lives in the
# management account, not this one (see 01-identity-center/dns.tf) — this
# assumes dns-zone-writer from the same base identity as the default provider
# above, exactly like external-dns.tf's IRSA role does at runtime for its own
# record writes.
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

provider "kubernetes" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
  token                  = data.aws_eks_cluster_auth.eks.token
}

provider "helm" {
  kubernetes = {
    host                   = module.eks.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
    token                  = data.aws_eks_cluster_auth.eks.token
  }
}
