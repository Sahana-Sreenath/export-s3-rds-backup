output "rds_s3_access_role" {
  value = aws_iam_role.rds_s3_access.arn
}

output "lambda_rds_export_access_role" {
  value = aws_iam_role.lambda_rds_export_access.arn
}
