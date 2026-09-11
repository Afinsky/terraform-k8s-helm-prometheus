variable "environment" {
  description = "Environment"
  type        = string
}

variable "profile" {
  description = "AWS Profile name. До первого apply никакого SSO-профиля lab-admin ещё не существует — курица и яйцо. Используй тот же профиль, под которым сейчас реально работаешь (например, тот же \"terraform\", что и в environments/develop)."
  type        = string
}

variable "region" {
  type        = string
  default     = "us-east-1"
  description = "Регион. IAM Identity Center живёт в одном регионе — выбери тот же, где будет кластер лабы."
}

variable "email" {
  type        = string
  default     = "a.afinsky@gmail.com"
  description = "Твой почтовый ящик. Для aliaksei/alice/bob используются алиасы вида you+admin@gmail.com — все письма придут на этот же ящик."
}
