variable "name_terrafrom_state_s3" {
  description = "Name of the S3 bucket used to store Terraform state"
  default     = ""
  type        = string
}
variable "tags" {
  description = "Tags to apply to all resources created by this module"
  default     = {}
  type        = map(string)
}
variable "force_destroy" {
  description = "Whether to allow the S3 state bucket to be destroyed even if it contains objects"
  type        = bool
  default     = false
}
variable "versioning" {
  description = "Versioning configuration for the S3 state bucket"
  type        = map(string)
  default     = {}
}
variable "server_side_encryption_configuration" {
  description = "Server-side encryption configuration for the S3 state bucket"
  type        = any
  default     = {}
}
