resource "helm_release" "ingress_nginx" {
  name             = "ingress-nginx"
  repository       = "https://kubernetes.github.io/ingress-nginx"
  chart            = "ingress-nginx"
  namespace        = "ingress-nginx"
  create_namespace = true
  version          = "4.15.1" # Verified live via `helm search repo ingress-nginx/ingress-nginx --versions` on 2026-08-11.
  values           = [file("./../../k8s/helm/nginx.yaml")]
  set = [
    {
      name  = "controller.service.annotations.service\\.beta\\.kubernetes\\.io/aws-load-balancer-ssl-cert"
      value = module.acm_backend.acm_certificate_arn
      type  = "string"
    }
  ]

  # The helm provider authenticates as the cluster creator (user/Terraform).
  # Ensure the EKS access entry granting that principal admin exists before
  # attempting the install, otherwise the API server returns 401.
  #
  # Also wait for the AWS Load Balancer Controller: this Service carries
  # aws-load-balancer-* annotations that only that controller understands
  # (see lbc.tf and nginx.yaml).
  depends_on = [module.eks, helm_release.aws_load_balancer_controller]
}
