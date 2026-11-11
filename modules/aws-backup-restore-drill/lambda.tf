data "archive_file" "validator" {
  type        = "zip"
  output_path = "${path.module}/build/${var.name}-validator.zip"

  source {
    content  = file("${path.module}/lambda/handler.py")
    filename = "handler.py"
  }

  # Packaged only when a CA bundle is supplied. The validator verifies the
  # server certificate when this file exists.
  dynamic "source" {
    for_each = var.db_ca_bundle_file == null ? [] : [var.db_ca_bundle_file]

    content {
      content  = file(source.value)
      filename = "rds-ca.pem"
    }
  }
}

resource "aws_cloudwatch_log_group" "validator" {
  name              = "/aws/lambda/${local.validator_name}"
  retention_in_days = var.log_retention_days
  kms_key_id        = var.kms_key_arn
  tags              = var.tags
}

resource "aws_lambda_function" "validator" {
  function_name = local.validator_name
  description   = "Validates databases restored by the ${local.plan_name} restore testing plan"
  role          = aws_iam_role.validator.arn

  filename         = data.archive_file.validator.output_path
  source_code_hash = data.archive_file.validator.output_base64sha256
  handler          = "handler.handler"
  runtime          = "python3.13"
  architectures    = ["arm64"]
  layers           = var.lambda_layer_arns

  timeout     = var.validator_timeout_seconds
  memory_size = var.validator_memory_mb
  kms_key_arn = var.kms_key_arn

  vpc_config {
    subnet_ids         = var.validator_subnet_ids
    security_group_ids = [aws_security_group.validator.id]
  }

  environment {
    variables = {
      ENGINE                 = var.engine
      DB_NAME                = var.db_name
      CREDENTIALS_SECRET_ARN = var.credentials_secret_arn == null ? "" : var.credentials_secret_arn
      SQL_CHECKS             = jsonencode(var.sql_checks)
      READY_TIMEOUT_SECONDS  = tostring(var.validator_timeout_seconds)
      METRIC_NAMESPACE       = var.metric_namespace
      PLAN_NAME              = local.plan_name
      SNS_TOPIC_ARN          = var.sns_topic_arn == null ? "" : var.sns_topic_arn
      NOTIFY_ON_SUCCESS      = tostring(var.notify_on_success)
    }
  }

  tags = var.tags

  depends_on = [
    aws_cloudwatch_log_group.validator,
    aws_iam_role_policy.validator,
    aws_iam_role_policy_attachment.validator_vpc,
  ]
}

# The validator reports every outcome itself, including its own errors. A retry
# would validate the same restore job twice, and a verdict can be set only once.
# If the function crashes or times out before it can report, the failed event
# goes to the SNS topic, so a drill never disappears silently.
resource "aws_lambda_function_event_invoke_config" "validator" {
  function_name          = aws_lambda_function.validator.function_name
  maximum_retry_attempts = 0

  dynamic "destination_config" {
    for_each = var.sns_topic_arn == null ? [] : [var.sns_topic_arn]

    content {
      on_failure {
        destination = destination_config.value
      }
    }
  }
}
