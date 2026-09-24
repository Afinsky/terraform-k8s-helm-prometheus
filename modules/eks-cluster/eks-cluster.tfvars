profile        = "terraform"
environment    = "dev"
region         = "us-east-1"
aws_account_id = "417886991962" # tflint fixture only — Terragrunt sets this from accounts/abotyan001/account.hcl
repo_root      = "../.."        # tflint fixture only — Terragrunt sets this to get_repo_root() for real runs.
# 2 levels: this module now lives at modules/eks-cluster/ (was accounts/abotyan001/us-east-1/develop/,
# 4 levels deep, hence the old "../../../..").
# EKS public API endpoint is restricted to this IP.
# Refresh it before applying if it's stale: curl -s https://checkip.amazonaws.com
my_ip_cidr = "83.175.181.227/32"

# tflint-only fixtures — see modules/identity-center/dns.tf for the real values
dns_zone_writer_role_arn = "arn:aws:iam::417886991962:role/dns-zone-writer"
dns_zone_id              = "Z03682881TYQWE74HYLWJ"
dns_zone_name            = "abotyan.click"

vpc = {
  homelab = {
    cidr             = "10.30.0.0/16"
    azs              = ["us-east-1c", "us-east-1f"]
    private_subnets  = ["10.30.10.0/24", "10.30.11.0/24"]
    public_subnets   = ["10.30.20.0/24", "10.30.21.0/24"]
    database_subnets = ["10.30.30.0/24", "10.30.31.0/24"]
  }
}
