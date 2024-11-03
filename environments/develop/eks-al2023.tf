module "ebs_csi_irsa_role" {
  source = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"

  role_name             = "${local.resource_name}-ebs-csi"
  attach_ebs_csi_policy = true

  oidc_providers = {
    ex = {
      provider_arn               = module.eks_al2023.oidc_provider_arn
      namespace_service_accounts = ["kube-system:ebs-csi-controller-sa"]
    }
  }
}

module "eks_al2023" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.0"

  cluster_name    = "${local.resource_name}-al2023"
  cluster_version = "1.31"

  # EKS Addons
  cluster_addons = {
    coredns                = {}
    eks-pod-identity-agent = {}
    kube-proxy             = {}
    vpc-cni                = {}

    aws-ebs-csi-driver = {
      service_account_role_arn = module.ebs_csi_irsa_role.iam_role_arn
      most_recent              = true
    }
  }


  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  self_managed_node_groups = {
    "${local.resource_name}" = {
      ami_type      = "AL2023_x86_64_STANDARD"
      instance_type = "t3.large" #"t3.medium" #"m6i.large"

      min_size = 3
      max_size = 5
      # This value is ignored after the initial creation
      # https://github.com/bryantbiggs/eks-desired-size-hack
      desired_size = 2

      # This is not required - demonstrates how to pass additional configuration to nodeadm
      # Ref https://awslabs.github.io/amazon-eks-ami/nodeadm/doc/api/
      cloudinit_pre_nodeadm = [
        {
          content_type = "application/node.eks.aws"
          content      = <<-EOT
            ---
            apiVersion: node.eks.aws/v1alpha1
            kind: NodeConfig
            spec:
              kubelet:
                config:
                  shutdownGracePeriod: 30s
                  featureGates:
                    DisableKubeletCloudCredentialProviders: true
          EOT
        }
      ]
    }
  }


  # Cluster access entry
  # To add the current caller identity as an administrator
  enable_cluster_creator_admin_permissions = true # THIS IS FIXED THE PROBLEM WITH ACCESS TO THE EKS CLUSTER:

  /*
  # module.eks_al2023.aws_eks_access_policy_association.this["cluster_creator_admin"] will be created
  + resource "aws_eks_access_policy_association" "this" {
      + associated_at = (known after apply)
      + cluster_name  = "dev-abotyan-al2023"
      + id            = (known after apply)
      + modified_at   = (known after apply)
      + policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
      + principal_arn = "arn:aws:iam::242906888793:role/aws-reserved/sso.amazonaws.com/AWSReservedSSO_AWSPowerUserAccess_8ceee21e3e493e23"

      + access_scope {
          + type = "cluster"
        }
    }
   */




  # access_entries = {
  #   # One access entry with a policy associated
  #   example = {
  #     kubernetes_groups = []
  #     principal_arn     = "arn:aws:sts::242906888793:assumed-role/AWSReservedSSO_AWSPowerUserAccess_8ceee21e3e493e23/AlexeyBotyan@coherentsolutions.com" #"arn:aws:iam::123456789012:role/something"
  #
  #     policy_associations = {
  #       example = {
  #         policy_arn = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSViewPolicy"
  #         access_scope = {
  #           namespaces = ["default"]
  #           type       = "namespace"
  #         }
  #       }
  #     }
  #   }
  # }

  cluster_endpoint_private_access = false
  cluster_endpoint_public_access  = true

  tags = local.common_tags
}
