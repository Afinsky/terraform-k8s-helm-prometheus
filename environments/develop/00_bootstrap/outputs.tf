output "terraform_state_bucket_id" {
  description = "ID of the S3 bucket used to store Terraform state"
  value       = module.backend.terraform_state_bucket_id
}

output "terraform_state_dynamodb_table_id" {
  description = "ID of the DynamoDB table used for Terraform state locking"
  value       = module.backend.terraform_state_dynamodb_table_id
}
