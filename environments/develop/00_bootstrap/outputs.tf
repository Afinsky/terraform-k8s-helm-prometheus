output "terraform_state_bucket_id" {
  description = "ID of the S3 bucket used to store Terraform state"
  value       = module.backend.terraform_state_bucket_id
}
