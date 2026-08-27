# backend

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.3.2 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | >= 5.70 |

## Providers

No providers.

## Modules

| Name | Source | Version |
| ---- | ------ | ------- |
| <a name="module_s3"></a> [s3](#module\_s3) | github.com/terraform-aws-modules/terraform-aws-s3-bucket | v3.14.1 |

## Resources

No resources.

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_force_destroy"></a> [force\_destroy](#input\_force\_destroy) | Whether to allow the S3 state bucket to be destroyed even if it contains objects | `bool` | `false` | no |
| <a name="input_name_terrafrom_state_s3"></a> [name\_terrafrom\_state\_s3](#input\_name\_terrafrom\_state\_s3) | Name of the S3 bucket used to store Terraform state | `string` | `""` | no |
| <a name="input_server_side_encryption_configuration"></a> [server\_side\_encryption\_configuration](#input\_server\_side\_encryption\_configuration) | Server-side encryption configuration for the S3 state bucket | `any` | `{}` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Tags to apply to all resources created by this module | `map(string)` | `{}` | no |
| <a name="input_versioning"></a> [versioning](#input\_versioning) | Versioning configuration for the S3 state bucket | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_s3_bucket_arn"></a> [s3\_bucket\_arn](#output\_s3\_bucket\_arn) | ARN of the S3 bucket used to store Terraform state |
| <a name="output_terraform_state_bucket_id"></a> [terraform\_state\_bucket\_id](#output\_terraform\_state\_bucket\_id) | ID of the S3 bucket used to store Terraform state |
<!-- END_TF_DOCS -->
