# 00_bootstrap

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
| <a name="module_backend"></a> [backend](#module\_backend) | ../modules/backend | n/a |

## Resources

No resources.

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_environment"></a> [environment](#input\_environment) | Environment | `string` | n/a | yes |
| <a name="input_profile"></a> [profile](#input\_profile) | AWS Profile name | `string` | n/a | yes |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_terraform_state_bucket_id"></a> [terraform\_state\_bucket\_id](#output\_terraform\_state\_bucket\_id) | ID of the S3 bucket used to store Terraform state |
<!-- END_TF_DOCS -->
