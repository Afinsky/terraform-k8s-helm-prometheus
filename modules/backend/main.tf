module "s3" {
  source = "github.com/terraform-aws-modules/terraform-aws-s3-bucket?ref=v3.14.1"

  bucket                               = var.name_terrafrom_state_s3
  force_destroy                        = var.force_destroy
  versioning                           = var.versioning
  server_side_encryption_configuration = var.server_side_encryption_configuration
  attach_public_policy                 = false
  block_public_acls                    = true
  block_public_policy                  = true
  ignore_public_acls                   = true
  restrict_public_buckets              = true
  tags                                 = merge({ Name = var.name_terrafrom_state_s3 }, var.tags)
}

resource "aws_dynamodb_table" "this" {
  name         = var.name_lock_dynamodb
  billing_mode = "PAY_PER_REQUEST"
  #read_capacity  = 5
  #write_capacity = 5
  hash_key = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }

  tags = merge({ Name = var.name_lock_dynamodb }, var.tags)
}