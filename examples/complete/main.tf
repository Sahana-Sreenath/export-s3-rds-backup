module "export_s3_rds_backup_complete" {
  source         = ../../export-s3-rds-backup
  account_number = data.aws_caller_identity.current.account_id
  project        = local.project
  db_instance_id = local.db_instance_id
  common_tags    = local.common_tags
}
  
locals {
  aws_account_id = "123456789"
  aws_region     = "us-east-1"
  managed_by     = "terraform"
  db_instance_id = "aws-rds-instance-id"
  project        = "test-backup"

  common_tags = {
    label       = "complete-rds-db-backup"
    project     = "test"
    managed_by  = local.managed_by
    cluster_id  = "db_name"
    environment = "development"
    expiration  = "never"
  }
