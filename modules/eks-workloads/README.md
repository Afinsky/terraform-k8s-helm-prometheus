# eks-workloads

Everything that talks to the Kubernetes API for the cluster `modules/eks-cluster`
creates — IRSA controllers (aws-load-balancer-controller, external-dns,
external-secrets), ingress-nginx, the PLAT-101 access-lab namespaces/RBAC,
and the sample apps. Applied and destroyed as its own Terragrunt layer,
after `eks-cluster` — see that module's README for why (destroy ordering:
this layer's helm releases/manifests are torn down while the cluster and its
controllers are still live, so an ALB/NLB a controller created actually gets
deprovisioned before the VPC/subnets underneath it are destroyed).

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.3.2 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | >= 6.60.0 |
| <a name="requirement_helm"></a> [helm](#requirement\_helm) | >= 3.2.0 |
| <a name="requirement_kubernetes"></a> [kubernetes](#requirement\_kubernetes) | >= 3.2.1 |

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_aws"></a> [aws](#provider\_aws) | >= 6.60.0 |
| <a name="provider_helm"></a> [helm](#provider\_helm) | >= 3.2.0 |
| <a name="provider_kubernetes"></a> [kubernetes](#provider\_kubernetes) | >= 3.2.1 |

## Modules

No modules.

## Resources

| Name | Type |
| ---- | ---- |
| [aws_iam_policy.external_secrets](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_policy) | resource |
| [aws_iam_policy.lb_controller](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_policy) | resource |
| [aws_iam_role.external_dns](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role.external_secrets](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role.lb_controller](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role_policy.external_dns_assume_dns](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy) | resource |
| [aws_iam_role_policy_attachment.external_secrets](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_iam_role_policy_attachment.lb_controller](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [helm_release.aws_load_balancer_controller](https://registry.terraform.io/providers/hashicorp/helm/latest/docs/resources/release) | resource |
| [helm_release.external_dns](https://registry.terraform.io/providers/hashicorp/helm/latest/docs/resources/release) | resource |
| [helm_release.external_secrets](https://registry.terraform.io/providers/hashicorp/helm/latest/docs/resources/release) | resource |
| [helm_release.ingress_nginx](https://registry.terraform.io/providers/hashicorp/helm/latest/docs/resources/release) | resource |
| [kubernetes_manifest.app](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/manifest) | resource |
| [kubernetes_manifest.eks_access_lab_namespaces](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/manifest) | resource |
| [kubernetes_manifest.eks_access_lab_rolebindings](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/manifest) | resource |
| [kubernetes_manifest.external_secrets_cluster_store](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/manifest) | resource |
| [kubernetes_manifest.online_boutique](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/manifest) | resource |
| [aws_caller_identity.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/caller_identity) | data source |
| [aws_eks_cluster_auth.eks](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/eks_cluster_auth) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_acm_certificate_arn"></a> [acm\_certificate\_arn](#input\_acm\_certificate\_arn) | Validated backend ACM certificate ARN, from modules/eks-cluster's acm\_certificate\_arn output. Attached to ingress-nginx's Service via annotation. | `string` | n/a | yes |
| <a name="input_aws_account_id"></a> [aws\_account\_id](#input\_aws\_account\_id) | Expected AWS account ID (from account.hcl, passed by Terragrunt). Guards provider.tf's allowed\_account\_ids against an apply landing in the wrong AWS account/profile. | `string` | n/a | yes |
| <a name="input_cluster_certificate_authority_data"></a> [cluster\_certificate\_authority\_data](#input\_cluster\_certificate\_authority\_data) | Base64-encoded cluster CA cert, from modules/eks-cluster's cluster\_certificate\_authority\_data output. | `string` | n/a | yes |
| <a name="input_cluster_endpoint"></a> [cluster\_endpoint](#input\_cluster\_endpoint) | EKS API server endpoint, from modules/eks-cluster's cluster\_endpoint output. Used by the kubernetes/helm providers (provider.tf). | `string` | n/a | yes |
| <a name="input_cluster_name"></a> [cluster\_name](#input\_cluster\_name) | EKS cluster name, from modules/eks-cluster's cluster\_name output. | `string` | n/a | yes |
| <a name="input_dns_zone_name"></a> [dns\_zone\_name](#input\_dns\_zone\_name) | Domain name of the zone above (external-dns's domainFilters). | `string` | n/a | yes |
| <a name="input_dns_zone_writer_role_arn"></a> [dns\_zone\_writer\_role\_arn](#input\_dns\_zone\_writer\_role\_arn) | ARN of modules/identity-center's dns-zone-writer role, in the management account. external-dns's IRSA role assumes this at runtime to write into the Route53 zone, which lives in that account regardless of which account this module is applied into. | `string` | n/a | yes |
| <a name="input_environment"></a> [environment](#input\_environment) | Environment | `string` | n/a | yes |
| <a name="input_oidc_provider"></a> [oidc\_provider](#input\_oidc\_provider) | OIDC provider issuer URL (no leading https://), from modules/eks-cluster's oidc\_provider output. Used by every IRSA role's trust policy here. | `string` | n/a | yes |
| <a name="input_oidc_provider_arn"></a> [oidc\_provider\_arn](#input\_oidc\_provider\_arn) | OIDC provider ARN, from modules/eks-cluster's oidc\_provider\_arn output. Used by every IRSA role's trust policy here. | `string` | n/a | yes |
| <a name="input_profile"></a> [profile](#input\_profile) | AWS Profile name | `string` | n/a | yes |
| <a name="input_region"></a> [region](#input\_region) | value of the region where the resources will be created | `string` | `"us-east-1"` | no |
| <a name="input_repo_root"></a> [repo\_root](#input\_repo\_root) | Absolute path to the repo root, set via Terragrunt's get\_repo\_root(). Terragrunt always runs Terraform from a copy staged under .terragrunt-cache, so path.module-relative traversal up to files outside this stack (k8s/manifests/, policies/) can't be used — the depth of that staging copy isn't stable. | `string` | n/a | yes |
| <a name="input_vpc_id"></a> [vpc\_id](#input\_vpc\_id) | VPC ID, from modules/eks-cluster's vpc\_id output. aws-load-balancer-controller needs it to find subnets/security groups. | `string` | n/a | yes |

## Outputs

No outputs.
<!-- END_TF_DOCS -->
