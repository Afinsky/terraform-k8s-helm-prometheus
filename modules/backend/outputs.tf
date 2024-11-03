output "terraform_state_bucket_id" {
  value = module.s3.s3_bucket_id #aws_s3_bucket.this.id
}

output "s3_bucket_arn" {
  value = module.s3.s3_bucket_arn #aws_s3_bucket.this.arn
}

output "terraform_state_dynamodb_table_id" {
  value = aws_dynamodb_table.this.id
}