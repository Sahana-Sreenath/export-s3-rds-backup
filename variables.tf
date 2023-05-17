variable "project" {
  description = "Unique project name identifier for which the backup module needs to be triggered"
  type        = string
}

variable "common_tags" {
  description = "tags to attach to resources"
  type        = map(any)
}

variable "account_number" {
  description = "account number where the db instance exists and where the resources needs to be created"
  type        = string
}

variable "db_instance_id" {
  description = "DB instance identifier in the account above for which backup needs to be enabled"
  type        = string
}
