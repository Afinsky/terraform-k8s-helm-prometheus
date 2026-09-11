# AWS Load Balancer Controller (LBC)
#
# Replaces the legacy in-tree AWS cloud provider's Service-of-type-LoadBalancer
# reconciliation with the actively developed out-of-cluster controller. Without
# this, `service.beta.kubernetes.io/aws-load-balancer-*` annotations on the
# ingress-nginx Service (ingress-nginx.yaml) are handled by the legacy in-tree
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

# The Helm release itself moved to ArgoCD (gitops/platform/aws-load-balancer-controller/).
# Terraform's job ends here: create the ServiceAccount with its IRSA
# annotation already attached, so the chart (deployed with
# serviceAccount.create=false) never needs to know the role ARN. clusterName
# and region in the chart's values are plain literals in gitops/ instead of
# Terraform `set` values - both are deterministic from develop.tfvars, not
# discovered at apply time. vpcId is left unset in values on purpose: the
# controller auto-discovers it from the node's EC2 instance metadata, which
# avoids needing a second Terraform-computed literal (the VPC ID isn't
# predictable the way clusterName/region are).
resource "kubernetes_service_account_v1" "lb_controller" {
  metadata {
    name      = "aws-load-balancer-controller"
    namespace = "kube-system"
    annotations = {
      "eks.amazonaws.com/role-arn" = aws_iam_role.lb_controller.arn
    }
  }

  depends_on = [module.eks, aws_iam_role_policy_attachment.lb_controller]
}
