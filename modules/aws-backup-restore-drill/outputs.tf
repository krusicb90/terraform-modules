output "restore_testing_plan_name" {
  description = "Name of the restore testing plan."
  value       = aws_backup_restore_testing_plan.this.name
}

output "restore_testing_plan_arn" {
  description = "ARN of the restore testing plan."
  value       = aws_backup_restore_testing_plan.this.arn
}

output "restore_testing_selection_name" {
  description = "Name of the restore testing selection."
  value       = aws_backup_restore_testing_selection.this.name
}

output "restore_role_arn" {
  description = "ARN of the role AWS Backup uses to restore."
  value       = aws_iam_role.restore.arn
}

output "validator_function_name" {
  description = "Name of the validator function."
  value       = aws_lambda_function.validator.function_name
}

output "validator_function_arn" {
  description = "ARN of the validator function."
  value       = aws_lambda_function.validator.arn
}

output "validator_role_arn" {
  description = "ARN of the validator function's role. Use it to grant access to a customer managed KMS key."
  value       = aws_iam_role.validator.arn
}

output "validator_security_group_id" {
  description = "Security group of the validator function."
  value       = aws_security_group.validator.id
}

output "restored_security_group_id" {
  description = "Security group attached to every restored test instance."
  value       = aws_security_group.restored.id
}

output "event_rule_arn" {
  description = "ARN of the EventBridge rule that triggers the validator."
  value       = aws_cloudwatch_event_rule.restore_job.arn
}

output "metric_namespace" {
  description = "CloudWatch namespace of the DrillSuccess and RestoreDurationSeconds metrics."
  value       = var.metric_namespace
}
