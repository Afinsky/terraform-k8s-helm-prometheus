resource "helm_release" "ingress_nginx" {
  name             = "ingress-nginx"
  repository       = "https://kubernetes.github.io/ingress-nginx"
  chart            = "ingress-nginx"
  namespace        = "ingress-nginx"
  create_namespace = true
  version          = "4.15.1" # Verified live via `helm search repo ingress-nginx/ingress-nginx --versions` on 2026-08-11.
  values           = [file("${var.repo_root}/k8s/helm/ingress-nginx.yaml")]
  set = [
    {
      name  = "controller.service.annotations.service\\.beta\\.kubernetes\\.io/aws-load-balancer-ssl-cert"
      value = var.acm_certificate_arn
      type  = "string"
    }
  ]

  # Destroy-time safety: this Service is what actually owns the ALB/NLB (via
  # the LB Controller, still up at this point - see depends_on below and
  # its own file for why it's destroyed after this release, not before).
  # Same deregistration-delay reasoning as that file's timeout comment.
  wait    = true
  timeout = 600

  # Wait for the AWS Load Balancer Controller: this Service carries
  # aws-load-balancer-* annotations that only that controller understands
  # (see load-balancer-controller.tf and ingress-nginx.yaml).
  depends_on = [helm_release.aws_load_balancer_controller]
}
