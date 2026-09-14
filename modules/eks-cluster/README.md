# eks-cluster

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.3.2 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | >= 6.60.0 |
| <a name="requirement_helm"></a> [helm](#requirement\_helm) | >= 3.2.0 |
| <a name="requirement_kubernetes"></a> [kubernetes](#requirement\_kubernetes) | >= 3.2.1 |
| <a name="requirement_random"></a> [random](#requirement\_random) | >= 3.6.0 |

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_aws"></a> [aws](#provider\_aws) | >= 6.60.0 |
| <a name="provider_helm"></a> [helm](#provider\_helm) | >= 3.2.0 |
| <a name="provider_kubernetes"></a> [kubernetes](#provider\_kubernetes) | >= 3.2.1 |

## Modules

| Name | Source | Version |
| ---- | ------ | ------- |
| <a name="module_acm_backend"></a> [acm\_backend](#module\_acm\_backend) | terraform-aws-modules/acm/aws | v6.3.0 |
| <a name="module_acm_backend_dns_validation"></a> [acm\_backend\_dns\_validation](#module\_acm\_backend\_dns\_validation) | terraform-aws-modules/acm/aws | v6.3.0 |
| <a name="module_eks"></a> [eks](#module\_eks) | terraform-aws-modules/eks/aws | v21.24.2 |
| <a name="module_vpc"></a> [vpc](#module\_vpc) | terraform-aws-modules/vpc/aws | v6.6.1 |

## Resources

| Name | Type |
| ---- | ---- |
| [aws_acm_certificate_validation.backend](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/acm_certificate_validation) | resource |
| [aws_ecr_repository.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ecr_repository) | resource |
| [aws_iam_policy.external_secrets](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_policy) | resource |
| [aws_iam_policy.lb_controller](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_policy) | resource |
| [aws_iam_role.ebs_csi_driver](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role.external_dns](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role.external_secrets](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role.lb_controller](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role.vpc_cni](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role_policy.external_dns_assume_dns](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy) | resource |
| [aws_iam_role_policy_attachment.ebs_csi_driver](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_iam_role_policy_attachment.external_secrets](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_iam_role_policy_attachment.lb_controller](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_iam_role_policy_attachment.vpc_cni](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
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
| [aws_iam_roles.sso](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_roles) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_aws_account_id"></a> [aws\_account\_id](#input\_aws\_account\_id) | Expected AWS account ID (from accounts/abotyan001/account.hcl, passed by Terragrunt). Guards provider.tf's allowed\_account\_ids against an apply landing in the wrong AWS account/profile. | `string` | n/a | yes |
| <a name="input_dns_zone_id"></a> [dns\_zone\_id](#input\_dns\_zone\_id) | Route53 hosted zone ID, from 01-identity-center's dns\_zone\_id output. The zone itself lives in the management account, not this one. | `string` | n/a | yes |
| <a name="input_dns_zone_name"></a> [dns\_zone\_name](#input\_dns\_zone\_name) | Domain name of the zone above, from 01-identity-center's dns\_zone\_name output. | `string` | n/a | yes |
| <a name="input_dns_zone_writer_role_arn"></a> [dns\_zone\_writer\_role\_arn](#input\_dns\_zone\_writer\_role\_arn) | ARN of 01-identity-center's dns-zone-writer role, in the management account. Assumed by the aws.dns provider (see provider.tf) and by external-dns's IRSA role (external-dns.tf) — the Route53 zone lives in that account regardless of which account this module is applied into. | `string` | n/a | yes |
| <a name="input_enable_flow_log"></a> [enable\_flow\_log](#input\_enable\_flow\_log) | Whether or not to enable VPC Flow Logs | `bool` | `false` | no |
| <a name="input_environment"></a> [environment](#input\_environment) | Environment | `string` | n/a | yes |
| <a name="input_my_ip_cidr"></a> [my\_ip\_cidr](#input\_my\_ip\_cidr) | Your public IP in x.x.x.x/32 format. Restricts the EKS public API endpoint (PLAT-101 lab, Phase 3). Get it with: curl -s https://checkip.amazonaws.com | `string` | n/a | yes |
| <a name="input_profile"></a> [profile](#input\_profile) | AWS Profile name | `string` | n/a | yes |
| <a name="input_region"></a> [region](#input\_region) | value of the region where the resources will be created | `string` | `"us-east-1"` | no |
| <a name="input_repo_root"></a> [repo\_root](#input\_repo\_root) | Absolute path to the repo root, set via Terragrunt's get\_repo\_root(). Terragrunt always runs Terraform from a copy staged under .terragrunt-cache, so path.module-relative traversal up to files outside this stack (k8s/manifests/, policies/) can't be used — the depth of that staging copy isn't stable. | `string` | n/a | yes |
| <a name="input_vpc"></a> [vpc](#input\_vpc) | VPC configuration keyed by network name | `any` | `null` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_access_entries"></a> [access\_entries](#output\_access\_entries) | Map of access entries created and their attributes. |
| <a name="output_cluster_endpoint"></a> [cluster\_endpoint](#output\_cluster\_endpoint) | The endpoint for the EKS Kubernetes API server. |
| <a name="output_cluster_name"></a> [cluster\_name](#output\_cluster\_name) | The name of the created EKS cluster. |
| <a name="output_cluster_version"></a> [cluster\_version](#output\_cluster\_version) | The version of Kubernetes running on the EKS cluster. |
| <a name="output_oidc_provider"></a> [oidc\_provider](#output\_oidc\_provider) | The OpenID Connect identity provider (issuer URL without leading `https://`). |
| <a name="output_oidc_provider_arn"></a> [oidc\_provider\_arn](#output\_oidc\_provider\_arn) | The ARN of the OIDC Provider for the EKS cluster. |
<!-- END_TF_DOCS -->
