# AWS Load Balancer Controller (LBC)
#
# Replaces the legacy in-tree AWS cloud provider's Service-of-type-LoadBalancer
# reconciliation with the actively developed out-of-cluster controller. Without
# this, `service.beta.kubernetes.io/aws-load-balancer-*` annotations on the
# ingress-nginx Service (nginx.yaml) are handled by the legacy in-tree
# integration, which only supports instance targets (NodePort -> kube-proxy ->
# pod, an extra hop) and a small, frozen annotation set.
#
# IAM policies JSON is the upstream-published policies for this controller version
# (https://github.com/kubernetes-sigs/aws-load-balancer-controller/blob/main/docs/install/iam_policy.json).
# Re-download it whenever the chart version below is bumped, since new
# controller features occasionally require new permissions.

resource "aws_iam_role" "lb_controller" {
  name               = "${local.prefix}-aws-lb-controller"
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
          "${module.eks.oidc_provider}:sub": "system:serviceaccount:kube-system:aws-load-balancer-controller",
          "${module.eks.oidc_provider}:aud": "sts.amazonaws.com"
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

resource "aws_iam_policy" "lb_controller" {
  name   = "${local.prefix}-aws-lb-controller"
  policy = file("${path.module}/../../policies/iam-policy-aws-load-balancer-controller.json")
}

resource "aws_iam_role_policy_attachment" "lb_controller" {
  role       = aws_iam_role.lb_controller.name
  policy_arn = aws_iam_policy.lb_controller.arn
}

resource "helm_release" "aws_load_balancer_controller" {
  name             = "aws-load-balancer-controller"
  repository       = "https://aws.github.io/eks-charts"
  chart            = "aws-load-balancer-controller"
  namespace        = "kube-system"
  create_namespace = false
  version          = "3.5.0" # controller app version v3.5.0 - keep in step with the IAM policies JSON above.
  # Verified live via `helm search repo eks/aws-load-balancer-controller --versions`
  # on 2026-08-11. Chart versioning realigned with the app version at v3.0.0
  # (previously chart 1.x shipped app v2.x); v3.0.0's only behavioral change
  # relevant here is Gateway API reaching GA (opt-in, unused in this config) -
  # no new required IAM permissions, and it needs Kubernetes 1.22+ (cluster
  # runs 1.36). Re-run that helm search before every future version bump.

  set = [
    {
      name  = "clusterName"
      value = module.eks.cluster_name
    },
    {
      name  = "region"
      value = var.region
    },
    {
      name  = "vpcId"
      value = module.vpc.vpc_id
    },
    {
      name  = "serviceAccount.create"
      value = "true"
    },
    {
      name  = "serviceAccount.name"
      value = "aws-load-balancer-controller"
    },
    {
      name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
      value = aws_iam_role.lb_controller.arn
      type  = "string"
    }
  ]

  # Same access-entry ordering constraint as the ingress-nginx release: the
  # helm provider must be able to reach the API server as an admin principal.
  depends_on = [module.eks, aws_iam_role_policy_attachment.lb_controller]
}
