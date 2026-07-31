# __generated__ by Terraform
# Please review these resources and move them into your main configuration files.

# __generated__ by Terraform from "AmazonEKSLoadBalancerControllerRole"
resource "aws_iam_role" "controller_role" {
  assume_role_policy = jsonencode({
    Statement = [{
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "oidc.eks.us-east-1.amazonaws.com/id/19855968337B7CF00BEC11C1E6350065:aud" = "sts.amazonaws.com"
          "oidc.eks.us-east-1.amazonaws.com/id/19855968337B7CF00BEC11C1E6350065:sub" = "system:serviceaccount:kube-system:aws-load-balancer-controller"
        }
      }
      Effect = "Allow"
      Principal = {
        Federated = "arn:aws:iam::242906888793:oidc-provider/oidc.eks.us-east-1.amazonaws.com/id/19855968337B7CF00BEC11C1E6350065"
      }
    }]
    Version = "2012-10-17"
  })
  description           = null
  force_detach_policies = false
  max_session_duration  = 3600
  name                  = "AmazonEKSLoadBalancerControllerRole"
  name_prefix           = null
  path                  = "/"
  permissions_boundary  = null
  tags = {
    "alpha.eksctl.io/cluster-name"                = "dev-abotyan-al2023"
    "alpha.eksctl.io/eksctl-version"              = "0.194.0"
    "alpha.eksctl.io/iamserviceaccount-name"      = "kube-system/aws-load-balancer-controller"
    "eksctl.cluster.k8s.io/v1alpha1/cluster-name" = "dev-abotyan-al2023"
  }
  tags_all = {
    "alpha.eksctl.io/cluster-name"                = "dev-abotyan-al2023"
    "alpha.eksctl.io/eksctl-version"              = "0.194.0"
    "alpha.eksctl.io/iamserviceaccount-name"      = "kube-system/aws-load-balancer-controller"
    "eksctl.cluster.k8s.io/v1alpha1/cluster-name" = "dev-abotyan-al2023"
  }
}
# OKAY
module "load_balancer_controller_irsa_role" {
  source = "github.com/terraform-aws-modules/terraform-aws-iam//modules/iam-role-for-service-accounts-eks?ref=v5.48.0"

  role_name = "load-balancer-controller"
  #attach_load_balancer_controller_policy = true
  force_detach_policies = false
  role_policy_arns = {
    AmazonEKSLoadBalancerControllerRole = "arn:aws:iam::242906888793:policy/AWSLoadBalancerControllerIAMPolicy"
  }
  oidc_providers = {
    ex = {
      provider_arn               = module.eks_al2023.oidc_provider_arn
      namespace_service_accounts = ["kube-system:aws-load-balancer-controller"]
    }
  }

  tags = {
    "alpha.eksctl.io/cluster-name"                = "dev-abotyan-al2023"
    "alpha.eksctl.io/iamserviceaccount-name"      = "kube-system/aws-load-balancer-controller"
    "alpha.eksctl.io/eksctl-version"              = "0.194.0"
    "eksctl.cluster.k8s.io/v1alpha1/cluster-name" = "dev-abotyan-al2023"
  }
}

#eksctl create iamserviceaccount --cluster=dev-abotyan-al2023 --namespace=kube-system --name=aws-load-balancer-controller --role-name AmazonEKSLoadBalancerControllerRole --attach-policy-arn=arn:aws:iam::242906888793:policy/AWSLoadBalancerControllerIAMPolicy --approve --profile sandbox
#eksctl create iamserviceaccount --cluster=dev-abotyan-al2023 --namespace=kube-system --name=aws-load-balancer-controller --role-name AmazonEKSLoadBalancerControllerRole --attach-policy-arn=arn:aws:iam::242906888793:policy/AWSLoadBalancerControllerIAMPolicy --approve --override-existing-serviceaccounts --profile sandbox