profile = "sandbox"
environment = "dev"

VPC = {
  csai = {
    cidr             = "10.30.0.0/16"
    azs              = ["us-east-1c", "us-east-1f"]
    private_subnets  = ["10.30.10.0/24", "10.30.11.0/24"]
    public_subnets   = ["10.30.20.0/24", "10.30.21.0/24"]
    database_subnets = ["10.30.30.0/24", "10.30.31.0/24"]
  }
}