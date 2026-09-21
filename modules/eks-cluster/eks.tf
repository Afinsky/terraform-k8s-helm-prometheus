module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "v21.24.2"

  name                                   = local.cluster_name
  kubernetes_version                     = "1.36"
  enabled_log_types                      = ["api", "audit", "authenticator"] # audit -> who did what; authenticator -> who tried to log in
  cloudwatch_log_group_retention_in_days = 30
  endpoint_public_access                 = true
  endpoint_public_access_cidrs           = [var.my_ip_cidr]

  # Access entries only, no aws-auth ConfigMap — the modern, EKS-native way
  # to grant IAM principals Kubernetes access (see eks-access.tf).
  authentication_mode = "API"

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
      most_recent    = true
      before_compute = true
    }
    vpc-cni = {
      most_recent              = true
      service_account_role_arn = aws_iam_role.vpc_cni.arn
      before_compute           = true
    }
  }

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  eks_managed_node_groups = {
    # Primary capacity. min < max (was a fixed min=max=desired=2) so Cluster
    # Autoscaler (modules/eks-workloads/cluster-autoscaler.tf) has room to
    # actually scale - desired_size only sets the size at creation time, the
    # eks-managed-node-group submodule's own aws_eks_node_group resource
    # ignore_changes[scaling_config[0].desired_size] unconditionally, so CA
    # freely moves it afterward without fighting Terraform on every apply.
    generalworkload-v4 = {
      min_size       = 2
      max_size       = 2
      desired_size   = 2
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
      tags = local.cluster_autoscaler_tags
    }

    # Fallback capacity: min=desired=0, so this costs nothing while the SPOT
    # group above has capacity. Only exists so a SPOT-wide interruption
    # (AWS reclaiming an entire capacity pool, which can hit every SPOT node
    # at once - not just one at a time) has somewhere for CA to schedule
    # replacement nodes instead of the cluster going fully unschedulable.
    ondemand-fallback = {
      min_size       = 0
      max_size       = 2
      desired_size   = 0
      instance_types = ["t3.medium"]
      capacity_type  = "ON_DEMAND"
      disk_size      = 60
      ebs_optimized  = true
      iam_role_additional_policies = {
        ssm_access        = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
        cloudwatch_access = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
        service_role_ssm  = "arn:aws:iam::aws:policy/service-role/AmazonEC2RoleforSSM"
        default_policy    = "arn:aws:iam::aws:policy/AmazonSSMManagedEC2InstanceDefaultPolicy"
      }
      tags = local.cluster_autoscaler_tags
    }
  }

  # false on purpose: true grants the identity Terraform runs
  # as an invisible admin access entry that never shows up in
  # `aws eks list-access-entries`. Made it explicit below ("terraform" entry)
  # instead - every helm_release/kubernetes_manifest resource in this
  # environment authenticates as that same identity and needs it.
  enable_cluster_creator_admin_permissions = false

  access_entries = merge(
    {
      # The identity that actually applies this stack (see terragrunt.hcl's
      # `profile`) and the day-to-day operator identity, in every account -
      # both are the same SSO role. Previously this granted admin to
      # "arn:...:user/Terraform" / "arn:...:user/aliaksei", static IAM users
      # that predate the move to Identity Center/SSO and don't actually exist
      # in any account anymore - AWS rejects an access entry for a principal
      # ARN that doesn't exist ("invalid principal"), which silently meant
      # *no one* had cluster-admin here.
      "devops-admin" = {
        # "devops-admins" (matches the Identity Center group name) is also a
        # real Kubernetes RBAC group here - see
        # modules/eks-workloads/rbac.tf's ClusterRoleBinding to cluster-admin.
        # The AWS access policy below is separate/redundant with that (EKS's
        # own permission system, not native RBAC) but harmless to keep - it's
        # what shows this principal as "admin" in the EKS console.
        kubernetes_groups = ["devops-admins"]
        principal_arn     = local.sso_role_arn.devops_admin
        policy_associations = {
          admin = {
            policy_arn = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
            access_scope = {
              type = "cluster"
            }
          }
        }
      }
    },
    {
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
    },
    # SSO roles from modules/identity-center. See eks-access.tf.
    local.sso_access_entries
  )

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
