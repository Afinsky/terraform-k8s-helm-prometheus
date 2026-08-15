module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "v21.24.2"

  name                                   = "${local.resource_name}-k8s-cluster"
  kubernetes_version                     = "1.36"
  enabled_log_types                      = ["audit"]
  cloudwatch_log_group_retention_in_days = 30
  endpoint_public_access                 = true

  addons = {
    coredns = {
      most_recent                 = true
      resolve_conflicts_on_create = "OVERWRITE"
      configuration_values = jsonencode(
        {
          replicaCount = 1
        }
      )
    }
    kube-proxy = {
      most_recent = true
    }
    vpc-cni = {
      most_recent              = true
      service_account_role_arn = aws_iam_role.vpc_cni.arn
    }
  }

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  eks_managed_node_groups = {
    generalworkload-v4 = {
      min_size       = 1
      max_size       = 1
      desired_size   = 1
      instance_types = ["t3.medium"] # "m5a.xlarge"
      capacity_type  = "SPOT"
      disk_size      = 60
      ebs_optimized  = true
      iam_role_additional_policies = {
        ssm_access        = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
        cloudwatch_access = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
        service_role_ssm  = "arn:aws:iam::aws:policy/service-role/AmazonEC2RoleforSSM"
        default_policy    = "arn:aws:iam::aws:policy/AmazonSSMManagedEC2InstanceDefaultPolicy"
      }
    }
  }

  enable_cluster_creator_admin_permissions = true

  access_entries = {
    for k in local.eks_access_entries : k.username => {
      kubernetes_groups = []
      principal_arn     = k.username
      policy_associations = {
        single = {
          policy_arn = k.access_policy
          access_scope = {
            type = "cluster"
          }
        }
      }
    }
  }

  tags = local.common_tags
}

#Role for vpc cni
resource "aws_iam_role" "vpc_cni" {
  name               = "${local.prefix}-vpc-cni"
  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "${module.eks.oidc_provider_arn}"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "${module.eks.oidc_provider}:sub": "system:serviceaccount:kube-system:aws-node"
        }
      }
    }
  ]
}
EOF
}

resource "aws_iam_role_policy_attachment" "vpc_cni" {
  role       = aws_iam_role.vpc_cni.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
}

#Role for EBS CSI driver
resource "aws_iam_role" "ebs_csi_driver" {
  name               = "${local.prefix}-ebs-csi-driver"
  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "${module.eks.oidc_provider_arn}"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "${module.eks.oidc_provider}:sub": "system:serviceaccount:kube-system:ebs-csi-controller-sa"
        }
      }
    }
  ]
}
EOF
}

resource "aws_iam_role_policy_attachment" "ebs_csi_driver" {
  role       = aws_iam_role.ebs_csi_driver.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
}
