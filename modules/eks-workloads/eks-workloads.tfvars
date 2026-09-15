profile        = "terraform"
environment    = "dev"
region         = "us-east-1"
aws_account_id = "417886991962" # tflint fixture only — Terragrunt sets this from account.hcl
repo_root      = "../.."        # tflint fixture only — Terragrunt sets this to get_repo_root() for real runs

# tflint-only fixtures — see modules/identity-center/dns.tf for the real values
dns_zone_writer_role_arn = "arn:aws:iam::417886991962:role/dns-zone-writer"
dns_zone_name            = "abotyan.click"

# tflint-only fixtures — see modules/eks-cluster's outputs for the real
# values (this layer's terragrunt.hcl reads them via a `dependency` block)
cluster_name                       = "dev-me-k8s-cluster"
cluster_endpoint                   = "https://EXAMPLE1234567890.gr7.us-east-1.eks.amazonaws.com"
cluster_certificate_authority_data = "ZXhhbXBsZQ=="
oidc_provider                      = "oidc.eks.us-east-1.amazonaws.com/id/EXAMPLED539D4633E53DE1B71EXAMPLE"
oidc_provider_arn                  = "arn:aws:iam::417886991962:oidc-provider/oidc.eks.us-east-1.amazonaws.com/id/EXAMPLED539D4633E53DE1B71EXAMPLE"
vpc_id                             = "vpc-0123456789abcdef0"
acm_certificate_arn                = "arn:aws:acm:us-east-1:417886991962:certificate/00000000-0000-0000-0000-000000000000"
