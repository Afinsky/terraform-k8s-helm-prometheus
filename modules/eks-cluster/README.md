# eks-cluster

VPC, EKS control plane/node groups, and ACM only - pure AWS resources, no
Kubernetes/Helm provider anywhere in this module. Everything that talks to
the cluster's own API (controllers, ingress-nginx, sample apps) lives in the
sibling `modules/eks-workloads`, applied as a separate Terragrunt layer
after this one. That split exists specifically for safe `terraform destroy`:
destroying `eks-workloads` first, while this cluster and its controllers are
still up, lets the AWS Load Balancer Controller actually deprovision any
ALB/NLB it created before this module's VPC/subnets get destroyed - doing
it all in one state risked the LB (and its ENIs) outliving the helm
release that owned it, orphaning it and blocking subnet deletion.

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.3.2 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | >= 6.60.0 |
| <a name="requirement_random"></a> [random](#requirement\_random) | >= 3.6.0 |

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_aws"></a> [aws](#provider\_aws) | >= 6.60.0 |

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
| [aws_iam_role.ebs_csi_driver](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role.vpc_cni](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role_policy_attachment.ebs_csi_driver](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_iam_role_policy_attachment.vpc_cni](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_caller_identity.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/caller_identity) | data source |
| [aws_iam_roles.sso](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_roles) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_aws_account_id"></a> [aws\_account\_id](#input\_aws\_account\_id) | Expected AWS account ID (from accounts/abotyan001/account.hcl, passed by Terragrunt). Guards provider.tf's allowed\_account\_ids against an apply landing in the wrong AWS account/profile. | `string` | n/a | yes |
| <a name="input_dns_zone_id"></a> [dns\_zone\_id](#input\_dns\_zone\_id) | Route53 hosted zone ID, from 01-identity-center's dns\_zone\_id output. The zone itself lives in the management account, not this one. | `string` | n/a | yes |
| <a name="input_dns_zone_name"></a> [dns\_zone\_name](#input\_dns\_zone\_name) | Domain name of the zone above, from 01-identity-center's dns\_zone\_name output. | `string` | n/a | yes |
| <a name="input_dns_zone_writer_role_arn"></a> [dns\_zone\_writer\_role\_arn](#input\_dns\_zone\_writer\_role\_arn) | ARN of modules/identity-center's dns-zone-writer role, in the management account. Assumed by the aws.dns provider (see provider.tf) for this module's own ACM validation records - the Route53 zone lives in that account regardless of which account this module is applied into. | `string` | n/a | yes |
| <a name="input_enable_flow_log"></a> [enable\_flow\_log](#input\_enable\_flow\_log) | Whether or not to enable VPC Flow Logs | `bool` | `false` | no |
| <a name="input_environment"></a> [environment](#input\_environment) | Environment | `string` | n/a | yes |
| <a name="input_my_ip_cidr"></a> [my\_ip\_cidr](#input\_my\_ip\_cidr) | Your public IP in x.x.x.x/32 format. Restricts the EKS public API endpoint (PLAT-101 lab, Phase 3). Get it with: curl -s https://checkip.amazonaws.com | `string` | n/a | yes |
| <a name="input_profile"></a> [profile](#input\_profile) | AWS Profile name | `string` | n/a | yes |
| <a name="input_region"></a> [region](#input\_region) | value of the region where the resources will be created | `string` | `"us-east-1"` | no |
| <a name="input_vpc"></a> [vpc](#input\_vpc) | VPC configuration keyed by network name | `any` | `null` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_access_entries"></a> [access\_entries](#output\_access\_entries) | Map of access entries created and their attributes. |
| <a name="output_acm_certificate_arn"></a> [acm\_certificate\_arn](#output\_acm\_certificate\_arn) | ARN of the validated backend ACM certificate - consumed by modules/eks-workloads' ingress-nginx Service annotation. |
| <a name="output_cluster_certificate_authority_data"></a> [cluster\_certificate\_authority\_data](#output\_cluster\_certificate\_authority\_data) | Base64-encoded CA cert for the cluster - modules/eks-workloads' kubernetes/helm providers need this to authenticate. |
| <a name="output_cluster_endpoint"></a> [cluster\_endpoint](#output\_cluster\_endpoint) | The endpoint for the EKS Kubernetes API server. |
| <a name="output_cluster_name"></a> [cluster\_name](#output\_cluster\_name) | The name of the created EKS cluster. |
| <a name="output_cluster_version"></a> [cluster\_version](#output\_cluster\_version) | The version of Kubernetes running on the EKS cluster. |
| <a name="output_oidc_provider"></a> [oidc\_provider](#output\_oidc\_provider) | The OpenID Connect identity provider (issuer URL without leading `https://`). |
| <a name="output_oidc_provider_arn"></a> [oidc\_provider\_arn](#output\_oidc\_provider\_arn) | The ARN of the OIDC Provider for the EKS cluster. |
| <a name="output_vpc_id"></a> [vpc\_id](#output\_vpc\_id) | VPC ID - consumed by modules/eks-workloads' aws-load-balancer-controller (needs to know which VPC to find subnets/security groups in). |
<!-- END_TF_DOCS -->
