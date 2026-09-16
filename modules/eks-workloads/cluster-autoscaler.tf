# Cluster Autoscaler
#
# modules/eks-cluster/eks.tf's node groups used to be a fixed size (min=max
# =desired=2, SPOT-only) - no room to grow under load, and no recovery path
# if AWS reclaimed a SPOT instance the ASG couldn't immediately replace from
# the same capacity pool. That module's node groups now carry a min<max
# range plus a second, ON_DEMAND-only "ondemand-fallback" group (min=0) for
# exactly that case - this controller is what actually watches for
# unschedulable pods and scales either ASG to match, via the
# k8s.io/cluster-autoscaler/* tags module.eks propagates onto both.
#
# Same IRSA pattern as the other controllers here: a dedicated role trusting
# only this ServiceAccount, policy scoped to what the controller needs.
# Unlike external-dns/external-secrets, most cluster-autoscaler actions are
# read-only Describe* calls with no resource-level permission support in
# IAM (AWS requires Resource="*" for those) - the two mutating actions
# (SetDesiredCapacity, TerminateInstanceInAutoScalingGroup) are scoped to
# only ASGs carrying this cluster's own discovery tag, so it can't resize an
# unrelated ASG even in the same account.

resource "aws_iam_role" "cluster_autoscaler" {
  name               = "${local.prefix}-cluster-autoscaler"
  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "${var.oidc_provider_arn}"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "${var.oidc_provider}:sub": "system:serviceaccount:kube-system:cluster-autoscaler",
          "${var.oidc_provider}:aud": "sts.amazonaws.com"
        }
      }
    }
  ]
}
EOF

  tags = {
    environment = var.environment
    managed_by  = "terraform"
    project     = local.project_name
  }
}

resource "aws_iam_policy" "cluster_autoscaler" {
  name = "${local.prefix}-cluster-autoscaler"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "autoscaling:DescribeAutoScalingGroups",
          "autoscaling:DescribeAutoScalingInstances",
          "autoscaling:DescribeLaunchConfigurations",
          "autoscaling:DescribeScalingActivities",
          "autoscaling:DescribeTags",
          "ec2:DescribeInstanceTypes",
          "ec2:DescribeLaunchTemplateVersions",
        ]
        Resource = ["*"]
      },
      {
        Effect = "Allow"
        Action = [
          "autoscaling:SetDesiredCapacity",
          "autoscaling:TerminateInstanceInAutoScalingGroup",
          "autoscaling:UpdateAutoScalingGroup",
        ]
        Resource = ["*"]
        Condition = {
          StringEquals = {
            "autoscaling:ResourceTag/k8s.io/cluster-autoscaler/${var.cluster_name}" = "owned"
          }
        }
      },
    ]
  })
}

resource "aws_iam_role_policy_attachment" "cluster_autoscaler" {
  role       = aws_iam_role.cluster_autoscaler.name
  policy_arn = aws_iam_policy.cluster_autoscaler.arn
}

resource "helm_release" "cluster_autoscaler" {
  name             = "cluster-autoscaler"
  repository       = "https://kubernetes.github.io/autoscaler"
  chart            = "cluster-autoscaler"
  namespace        = "kube-system"
  create_namespace = false
  version          = "9.59.0" # controller app version v1.35.0.
  # Verified live via `helm search repo autoscaler/cluster-autoscaler --versions`
  # on 2026-09-17. One minor behind this cluster's Kubernetes 1.36 (eks.tf) -
  # within the project's supported skew (n to n-1); re-check the compatibility
  # table at https://github.com/kubernetes/autoscaler/blob/master/cluster-autoscaler/README.md#releases
  # before bumping kubernetes_version further.

  set = [
    {
      name  = "autoDiscovery.clusterName"
      value = var.cluster_name
    },
    {
      name  = "awsRegion"
      value = var.region
    },
    {
      name  = "cloudProvider"
      value = "aws"
    },
    {
      name  = "rbac.serviceAccount.create"
      value = "true"
    },
    {
      name  = "rbac.serviceAccount.name"
      value = "cluster-autoscaler"
    },
    {
      name  = "rbac.serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
      value = aws_iam_role.cluster_autoscaler.arn
      type  = "string"
    }
  ]

  depends_on = [aws_iam_role_policy_attachment.cluster_autoscaler]
}
