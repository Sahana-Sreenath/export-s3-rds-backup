# Create cloudwatch event rule to trigger rds export to s3 lambda
# the CloudWatch Events rule will trigger at midnight (0:00) on the last day of every month, regardless of the day of the week or the month of the year.
# L: Represents the day of the month field, which is set to "L" to denote the "last" day of the month.
# ?: Represents the day of the week field, which is set to "?" to indicate no specific value.
resource "aws_cloudwatch_event_rule" "backup_trigger" {
  name        = "rds_export_to_s3_lambda_trigger"
  description = "Trigger step function on a schedule"

  schedule_expression = "cron(0 0 L * ? *)"
}

resource "aws_cloudwatch_event_target" "step_function_target" {
  rule      = aws_cloudwatch_event_rule.backup_trigger.name
  arn       = aws_sfn_state_machine.rds_backup_notify_trigger.arn
  target_id = aws_sfn_state_machine.rds_backup_notify_trigger.name
}

# S3 Bucket module to create s3 bucket to store RDS snapshots
# encrypted with KMS key for each db instance backup
module "backup_rds_snapshot" {
  source  = "terraform-aws-modules/s3-bucket/aws"
  version = "~> 3.0"

  bucket              = "${var.project}-rds-backup"
  acl                 = "private"
  object_lock_enabled = true

  server_side_encryption_configuration = {
    rule = {
      apply_server_side_encryption_by_default = {
        kms_master_key_id = aws_kms_key.s3_lambda_encryption.id
        sse_algorithm     = "aws:kms"
      }
      bucket_key_enabled = true
    }
  }

  versioning = {
    status     = true
    mfa_delete = false
  }
  tags = var.common_tags
}

# Modify the number of years as per security compliance
resource "aws_s3_bucket_object_lock_configuration" "rds_backup_retention" {
  bucket = module.backup_rds_snapshot.s3_bucket_id

  rule {
    default_retention {
      mode  = "COMPLIANCE"
      years = 4
    }
  }
}

# KMS key to use to encrypt the exported snapshot in S3
resource "aws_kms_key" "s3_lambda_encryption" {
  description = "KMS key for s3 lambda data encryption"
  policy      = data.aws_iam_policy_document.s3_lambda_encryption.json
}

# Role to export RDS snapshot and store it in S3
resource "aws_iam_policy" "rds_s3_access" {
  name   = "${var.project}-rds-s3-access"
  policy = data.aws_iam_policy_document.rds_s3_access.json
}

resource "aws_iam_role" "rds_s3_access" {
  name = "${var.project}-rds-s3-access"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Sid    = ""
        Principal = {
          Service = "export.rds.amazonaws.com"
        },
        "Action" : "sts:AssumeRole"
      },
    ]
  })
  tags = var.common_tags
}

resource "aws_iam_role_policy_attachment" "rds_s3_access" {
  role       = aws_iam_role.rds_s3_access.name
  policy_arn = aws_iam_policy.rds_s3_access.arn
}

# IAM Role for lambda function
resource "aws_iam_policy" "lambda_access_to_rds" {
  name   = "${var.project}-rds-lambda"
  policy = data.aws_iam_policy_document.lambda_access_to_rds.json
}

resource "aws_iam_policy" "lambda_access_to_sns" {
  name   = "${var.project}-sns-access"
  policy = data.aws_iam_policy_document.lambda_access_to_sns.json
}

resource "aws_iam_role" "lambda_rds_export_access" {
  name = "${var.project}-rds-s3-export-function"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Sid    = ""
        Principal = {
          Service = "lambda.amazonaws.com"
        },
        "Action" : "sts:AssumeRole"
      },
    ]
  })
  tags = var.common_tags
}

resource "aws_iam_role_policy_attachment" "lambda_rds_export_access" {
  role       = aws_iam_role.lambda_rds_export_access.name
  policy_arn = aws_iam_policy.lambda_access_to_rds.arn
}

resource "aws_iam_role_policy_attachment" "lambda_rds_sns_access" {
  role       = aws_iam_role.lambda_rds_export_access.name
  policy_arn = aws_iam_policy.lambda_access_to_sns.arn
}

# Lambda module customized to run lambda function that triggers export-to-s3 task
# Required environment variables are DB_INSTANCE_ID, S3_BUCKET, IAM_ROLE and KMS_KEY
module "lambda_function" {
  source  = "terraform-aws-modules/lambda/aws"
  version = "~> 4.0"

  function_name = "${var.project}-export-rds-backup-function"
  handler       = "lambda_function.lambda_handler"
  runtime       = "python3.9"
  timeout       = 300

  environment_variables = {
    DB_INSTANCE_ID = var.db_instance_id
    S3_BUCKET      = module.backup_rds_snapshot.s3_bucket_id
    IAM_ROLE       = aws_iam_role.rds_s3_access.arn
    KMS_KEY        = aws_kms_key.s3_lambda_encryption.id
  }
  create_package         = false
  local_existing_package = "${path.module}/lambda_function.zip"
}

# This section is for sending notifications 

# Lambda module customized to run lambda function that triggers notification task
# Required environment variables are DB_INSTANCE_ID, SNS_TOPIC_ARN and SLACK_URL

module "notify_lambda_function" {
  source  = "terraform-aws-modules/lambda/aws"
  version = "~> 4.0"

  function_name = "${var.project}-backup-notify-function"
  handler       = "lambda_function.lambda_handler"
  runtime       = "python3.9"
  timeout       = 300

  environment_variables = {
    DB_INSTANCE_ID = var.db_instance_id
    SNS_TOPIC_ARN  = aws_sns_topic.rds_backup_notify.arn
    SLACK_URL      = replace(data.aws_secretsmanager_secret_version.slack_webhook_secret_version.secret_string,"^\"|\"$", "")
  }
  create_package         = false
  local_existing_package = "${path.module}/notify_lambda_function.zip"
}

resource "aws_sns_topic" "rds_backup_notify" {
  name = "${var.project}-rds-backup-notification"
}

# IAM Role for step function
resource "aws_iam_policy" "step_function_access_to_lambda" {
  name   = "${var.project}-sfn-db-backup"
  policy = data.aws_iam_policy_document.step_function_access_to_lambda.json
}

resource "aws_iam_role" "step_function_access_to_lambda" {
  name = "${var.project}-sfn-db-backup"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Sid    = ""
        Principal = {
          Service = "states.amazonaws.com"
        },
        "Action" : "sts:AssumeRole"
      },
    ]
  })
  tags = var.common_tags
}

resource "aws_iam_role_policy_attachment" "step_function_access_to_lambda" {
  role       = aws_iam_role.step_function_access_to_lambda.name
  policy_arn = aws_iam_policy.step_function_access_to_lambda.arn
}

# provides step function state machine resource
resource "aws_sfn_state_machine" "rds_backup_notify_trigger" {
  name       = "${var.project}-backup-sfn"
  role_arn   = aws_iam_role.step_function_access_to_lambda.arn
  definition = <<EOF
{
  "Comment": "Step function to trigger export to s3 lambda function",
  "StartAt": "Lambda Invoke",
  "States": {
    "Lambda Invoke": {
      "Type": "Task",
      "Resource": "arn:aws:states:::lambda:invoke",
      "OutputPath": "$.Payload",
      "Parameters": {
        "Payload.$": "$",
        "FunctionName": "${module.lambda_function.lambda_function_arn_static}:$LATEST"
      },
      "Retry": [
        {
          "ErrorEquals": [
            "Lambda.ServiceException",
            "Lambda.AWSLambdaException",
            "Lambda.SdkClientException",
            "Lambda.TooManyRequestsException"
          ],
          "IntervalSeconds": 2,
          "MaxAttempts": 6,
          "BackoffRate": 2
        }
      ],
      "Next": "Wait"
    },
    "Wait": {
      "Type": "Wait",
      "Seconds": 900,
      "Next": "Poll Task Status"
    },
    "Poll Task Status": {
      "Type": "Task",
      "Resource": "arn:aws:states:::lambda:invoke",
      "Parameters": {
        "FunctionName": "${module.notify_lambda_function.lambda_function_arn_static}:$LATEST"
      },
      "OutputPath": "$.Payload",
      "Retry": [
        {
          "ErrorEquals": [
            "Lambda.ServiceException",
            "Lambda.AWSLambdaException",
            "Lambda.SdkClientException",
            "Lambda.TooManyRequestsException"
          ],
          "IntervalSeconds": 1200,
          "MaxAttempts": 3,
          "BackoffRate": 2
        }
      ],
      "Next": "Wait for Export Task Status"
    },
    "Wait for Export Task Status": {
      "Type": "Choice",
      "Choices": [
        {
          "Variable": "$.export_task_status",
          "StringEquals": "STARTING",
          "Next": "Wait when in-progress"
        },
        {
          "Variable": "$.export_task_status",
          "StringEquals": "IN_PROGRESS",
          "Next": "Wait when in-progress"
        },
        {
          "Variable": "$.export_task_status",
          "StringEquals": "FAILED",
          "Next": "Send Notification"
        },
        {
          "Variable": "$.export_task_status",
          "StringEquals": "COMPLETE",
          "Next": "Send Notification"
        }
      ],
      "Default": "Wait when in-progress"
    },
    "Wait when in-progress": {
      "Type": "Wait",
      "Seconds": 1200,
      "Next": "Poll Task Status"
    },
    "Send Notification": {
      "Type": "Pass",
      "End": true
    }
  }
}
EOF
}
