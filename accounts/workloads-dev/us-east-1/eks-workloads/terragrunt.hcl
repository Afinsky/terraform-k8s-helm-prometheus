#-------------------------------------------------------------
# terragrunt.hcl
#
# - same modules/eks-workloads module as accounts/abotyan001/us-east-1/eks-workloads,
#   applied into the workloads-dev account instead
# - depends on ../eks-cluster (this account's own): see that layer's
#   terragrunt.hcl comment
# - backend key comes from state.hcl (see root.hcl); bucket/profile/role come
#   from account.hcl
#-------------------------------------------------------------

include {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = "${get_repo_root()}/modules/eks-workloads"
}

dependency "eks_cluster" {
  config_path = "../eks-cluster"

  mock_outputs = {
    cluster_name                       = "mock-cluster-name"
    cluster_endpoint                   = "https://mock.eks.amazonaws.com"
    cluster_certificate_authority_data = "LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSUMvekNDQWVlZ0F3SUJBZ0lVQ0RXTkd1d0EvdHVsaDJKQkRIRUNQWlVGSVJzd0RRWUpLb1pJaHZjTkFRRUwKQlFBd0R6RU5NQXNHQTFVRUF3d0ViVzlqYXpBZUZ3MHlOakE1TVRVeE5EVXhNVEphRncweU5qQTVNVFl4TkRVeApNVEphTUE4eERUQUxCZ05WQkFNTUJHMXZZMnN3Z2dFaU1BMEdDU3FHU0liM0RRRUJBUVVBQTRJQkR3QXdnZ0VLCkFvSUJBUUMwWFk5dGlhVGZXUFIrK2s3blVsanFqOEdHZGpxZUQ0Rmx3bFUvcE5zWVI3KzdKamNPaVVaNHZwaHYKZG9WVHl2TWF4eXlWbjM2VFRZOU5HMWVXVmpubkhpSDB6Smh4SnRmaVgzdkdmVGJjZFRhanJ6RGsxbmc3VkNGagphSlVEMlh5and1b1dqVXlZU1doTllIQ2dUYVBlVnVOajN3Q2k4cG0wcW8vYnVUL1R4QnNGQnVudEQ5OUNVNFdkCkxQSEwycFUrdHBYOThhNzJNL2htYVRwanFTSk4rTWFYZHVzVG5OVHVLVWhOeUtXd2xjRG51aVoxYlZDamJmQTMKQXlIbkZYT2pyTHRIKytMZWlkc0ZjK0s1QU1vdVJvV3R1dFVzTjhkcHMxbFhINXRMMGZFU1R0QU82OGEzVmhWYQpTRUhSUGNxb2FOY0dhcmRhOFZ3TDYzcHZ2SXBGQWdNQkFBR2pVekJSTUIwR0ExVWREZ1FXQkJRdnhFU0dyaHI5CnJBUUcvbjlTRUlnWFkzdG5QREFmQmdOVkhTTUVHREFXZ0JRdnhFU0dyaHI5ckFRRy9uOVNFSWdYWTN0blBEQVAKQmdOVkhSTUJBZjhFQlRBREFRSC9NQTBHQ1NxR1NJYjNEUUVCQ3dVQUE0SUJBUUNJbnY4eXdMakpwZEV2d2txLwp1TXJQekM3UjMxeG5tbXhQQ0ZnNXMxZG1YdHZaeXpxVEZLT0tUd2pPVlJGNzI4TldKZGtNNEhzQ21selJFdmR4CkkxK0pXM2xibWVSOExxTHp2K0Vnei81VXBKR1QvbXEwR3pDcjV1TzNab1dXTVBJVDJxb2dyRWNwbk9zNmtKc3gKT2JJcGwwNytDT0J1ZytYRHNiYTBOSWNmalBlNGtWdDdTd1dhS1NoUTF0TjV4WFg2ZEFlK0U0MEUwaHBSNzBBKwo5ZG9SdmZvN1RxRldkUnQ2YkFtdGFITlplSTg2K01uSWxsSmdkaDZ0ZmZJWFJkcGgxNFkrRnFROUlCZkwwS2RPClR0QlJ2M0l2K3pTZTRNaE90a3hCUW55bStNL0duTEs3TkJpTEtxaGc5ZU4zTlFqNlZWc1k4NUpVcTM1ZEJjaFcKYXlXcQotLS0tLUVORCBDRVJUSUZJQ0FURS0tLS0tCg=="
    oidc_provider                      = "oidc.eks.us-east-1.amazonaws.com/id/MOCK"
    oidc_provider_arn                  = "arn:aws:iam::000000000000:oidc-provider/oidc.eks.us-east-1.amazonaws.com/id/MOCK"
    vpc_id                             = "vpc-mock"
    acm_certificate_arn                = "arn:aws:acm:us-east-1:000000000000:certificate/mock"
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan", "init"]
}

inputs = {
  # SSO profile for account_id 841775659851, role "devops-admin" — that
  # permission set is assigned org-wide by modules/identity-center/permission_sets.tf,
  # so no new IAM role/trust policy was needed for this account.
  profile     = "workloads-dev-devops-admin"
  environment = "dev"
  region      = "us-east-1"
  repo_root   = get_repo_root()

  cluster_name                       = dependency.eks_cluster.outputs.cluster_name
  cluster_endpoint                   = dependency.eks_cluster.outputs.cluster_endpoint
  cluster_certificate_authority_data = dependency.eks_cluster.outputs.cluster_certificate_authority_data
  oidc_provider                      = dependency.eks_cluster.outputs.oidc_provider
  oidc_provider_arn                  = dependency.eks_cluster.outputs.oidc_provider_arn
  vpc_id                             = dependency.eks_cluster.outputs.vpc_id
  acm_certificate_arn                = dependency.eks_cluster.outputs.acm_certificate_arn
}
