variable "name_lock_dynamodb" {
  default = ""
  type    = string
}
variable "name_terrafrom_state_s3" {
  default = ""
  type    = string
}
variable "tags" {
  default = {}
  type    = map(string)
}
variable "force_destroy" {
  type    = bool
  default = false
}
variable "versioning" {
  type    = map(string)
  default = {}
}
variable "server_side_encryption_configuration" {
  type    = any
  default = {}
}
