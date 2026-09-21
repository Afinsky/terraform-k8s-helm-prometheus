terraform {
  required_version = ">= 1.3.2"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.60.0"
    }
    # github_oidc.tf only: derives the GitHub OIDC provider's thumbprint
    # live instead of hardcoding one.
    tls = {
      source  = "hashicorp/tls"
      version = ">= 4.0.0"
    }
  }
}
