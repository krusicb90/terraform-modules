# --- Role AWS Backup uses to create the restored instance ---------------------

resource "aws_iam_role" "restore" {
  name = "${var.name}-restore"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "backup.amazonaws.com" }
    }]
  })

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "restore" {
  role       = aws_iam_role.restore.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/service-role/AWSBackupServiceRolePolicyForRestores"
}

# --- Role of the validator function --------------------------------------------

locals {
  # Restore testing always names the instances it creates with this prefix.
  restored_instance_arn = "arn:${data.aws_partition.current.partition}:rds:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:db:awsbackup-restore-test-*"

  validator_statements = concat(
    [
      {
        Sid      = "ReadAndReportRestoreJobs"
        Effect   = "Allow"
        Action   = ["backup:DescribeRestoreJob", "backup:PutRestoreValidationResult"]
        Resource = "*"
      },
      {
        Sid      = "DescribeRestoredInstances"
        Effect   = "Allow"
        Action   = "rds:DescribeDBInstances"
        Resource = local.restored_instance_arn
      },
      {
        Sid       = "PublishDrillMetrics"
        Effect    = "Allow"
        Action    = "cloudwatch:PutMetricData"
        Resource  = "*"
        Condition = { StringEquals = { "cloudwatch:namespace" = var.metric_namespace } }
      },
    ],
    var.credentials_secret_arn == null ? [] : [{
      Sid      = "ReadDatabaseCredentials"
      Effect   = "Allow"
      Action   = "secretsmanager:GetSecretValue"
      Resource = var.credentials_secret_arn
    }],
    var.credentials_kms_key_arn == null ? [] : [{
      Sid      = "DecryptDatabaseCredentials"
      Effect   = "Allow"
      Action   = "kms:Decrypt"
      Resource = var.credentials_kms_key_arn
    }],
    var.kms_key_arn == null ? [] : [{
      Sid      = "DecryptEnvironmentVariables"
      Effect   = "Allow"
      Action   = "kms:Decrypt"
      Resource = var.kms_key_arn
    }],
    var.sns_topic_arn == null ? [] : [{
      Sid      = "PublishDrillResult"
      Effect   = "Allow"
      Action   = "sns:Publish"
      Resource = var.sns_topic_arn
    }],
  )
}

resource "aws_iam_role" "validator" {
  name = "${var.name}-validator"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })

  tags = var.tags
}

resource "aws_iam_role_policy" "validator" {
  name = "validator"
  role = aws_iam_role.validator.id

  policy = jsonencode({
    Version   = "2012-10-17"
    Statement = local.validator_statements
  })
}

# Network interfaces for a function inside a VPC, and log delivery.
resource "aws_iam_role_policy_attachment" "validator_vpc" {
  role       = aws_iam_role.validator.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}
