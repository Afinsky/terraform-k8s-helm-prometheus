output "terraform_state_bucket_id" {
  description = "ID of the S3 bucket used to store Terraform state"
  value       = module.s3.s3_bucket_id #aws_s3_bucket.this.id
}

output "s3_bucket_arn" {
  description = "ARN of the S3 bucket used to store Terraform state"
  value       = module.s3.s3_bucket_arn #aws_s3_bucket.this.arn
}

output "terraform_state_dynamodb_table_id" {
  description = "ID of the DynamoDB table used for Terraform state locking"
  value       = aws_dynamodb_table.this.id
}
