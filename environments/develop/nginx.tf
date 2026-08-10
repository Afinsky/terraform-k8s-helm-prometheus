resource "helm_release" "ingress_nginx" {
  name             = "ingress-nginx"
  repository       = "https://kubernetes.github.io/ingress-nginx"
  chart            = "ingress-nginx"
  namespace        = "ingress-nginx"
  create_namespace = true
  version          = "4.10.0"
  values           = [file("./nginx.yaml")]
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
  depends_on = [module.eks]
}
