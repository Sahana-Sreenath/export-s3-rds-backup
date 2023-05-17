data "aws_iam_policy_document" "s3_lambda_encryption" {

  statement {
    effect    = "Allow"
    actions   = ["kms:*"]
    resources = ["*"]
    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${var.account_number}:root"]
    }
  }

  statement {
    sid    = "Allow use of the key"
    effect = "Allow"
    principals {
      type = "AWS"
      identifiers = [
        aws_iam_role.rds_s3_access.arn,
        aws_iam_role.lambda_rds_export_access.arn,
      ]
    }
    actions = [
      "kms:Encrypt",
      "kms:Decrypt",
      "kms:ReEncrypt*",
      "kms:GenerateDataKey*",
      "kms:DescribeKey",
      "kms:CreateGrant",
      "kms:ListGrants"
    ]
  }
}

data "aws_iam_policy_document" "rds_s3_access" {
  statement {
    sid = ""

    effect = "Allow"
    actions = [
      "s3:ListBucket",
      "s3:ListAllMyBuckets",
      "s3:DeleteObject",
      "s3:Get*",
      "s3:PutObject",
      "s3:ReplicateDelete",
      "s3:ListMultipartUploadParts"
    ]

    resources = [
      module.backup_rds_snapshot.s3_bucket_arn,
      "${module.backup_rds_snapshot.s3_bucket_arn}/*"
    ]
  }
}

data "aws_iam_policy_document" "lambda_access_to_rds" {
  version = "2012-10-17"
  statement {
    effect = "Allow"

    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents"
    ]

    resources = ["arn:aws:logs:*:*:*"]
  }

  statement {
    effect = "Allow"

    actions = [
      "rds:DescribeDBSnapshots",
      "rds:DeleteDBSnapshot",
      "rds:CopyDBSnapshot",
      "rds:StartExportTask",
      "rds:DescribeDBInstances",
      "rds:DescribeExportTasks",
      "iam:PassRole"
    ]

    resources = ["*"]
  }
}

data "aws_iam_policy_document" "lambda_access_to_sns" {
  version = "2012-10-17"
  statement {
    effect = "Allow"

    actions = [
      "sns:Publish"
    ]

    resources = ["${aws_sns_topic.rds_backup_notify.arn}"]
  }
}

data "aws_iam_policy_document" "step_function_access_to_lambda" {
  version = "2012-10-17"
  statement {
    effect = "Allow"

    actions = [
      "lambda:InvokeFunction"
    ]

    resources = ["${module.lambda_function.lambda_function_arn}:*",
      "${module.notify_lambda_function.lambda_function_arn}:*"
    ]
  }

  statement {
    effect = "Allow"

    actions = [
      "lambda:InvokeFunction"
    ]

    resources = ["${module.lambda_function.lambda_function_arn}",
      "${module.notify_lambda_function.lambda_function_arn}"
    ]
  }
}

data "archive_file" "lambda_function" {
  type        = "zip"
  source_dir  = "${path.module}/lambda_function"
  output_path = "${path.module}/lambda_function.zip"
}

data "archive_file" "notify_lambda_function" {
  type        = "zip"
  source_dir  = "${path.module}/notify_lambda_function"
  output_path = "${path.module}/notify_lambda_function.zip"
}

data "aws_secretsmanager_secret" "slack_webhook_url" {
  name = "slack_webhook_url"
}

data "aws_secretsmanager_secret_version" "slack_webhook_secret_version" {
  secret_id = data.aws_secretsmanager_secret.slack_webhook_url.id
}
