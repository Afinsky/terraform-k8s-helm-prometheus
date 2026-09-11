profile     = "terraform"
environment = "dev"
region      = "us-east-1"
# PLAT-101 Phase 3: EKS public API endpoint is restricted to this IP.
# Refresh it before applying if it's stale: curl -s https://checkip.amazonaws.com
my_ip_cidr = "83.175.181.227/32"

vpc = {
  homelab = {
    cidr             = "10.30.0.0/16"
    azs              = ["us-east-1c", "us-east-1f"]
    private_subnets  = ["10.30.10.0/24", "10.30.11.0/24"]
    public_subnets   = ["10.30.20.0/24", "10.30.21.0/24"]
    database_subnets = ["10.30.30.0/24", "10.30.31.0/24"]
  }
}
