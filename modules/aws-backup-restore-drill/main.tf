data "aws_partition" "current" {}
data "aws_region" "current" {}
data "aws_caller_identity" "current" {}

locals {
  # Restore testing plan and selection names accept letters, digits and underscores only.
  plan_name      = replace(var.name, "-", "_")
  validator_name = "${var.name}-validator"
  select_by_tag  = length(var.protected_resource_tags) > 0

  # Module-owned keys come last so that a caller cannot move the restored copy
  # out of the isolated security group by accident.
  restore_metadata_overrides = merge(
    var.restore_metadata_overrides,
    var.restore_instance_class == null ? {} : { dbInstanceClass = var.restore_instance_class },
    {
      dbSubnetGroupName = var.restore_db_subnet_group_name
      # List values must be JSON-encoded strings.
      vpcSecurityGroupIds = jsonencode([aws_security_group.restored.id])
    },
  )
}

resource "aws_backup_restore_testing_plan" "this" {
  name                         = local.plan_name
  schedule_expression          = var.schedule_expression
  schedule_expression_timezone = var.schedule_expression_timezone
  start_window_hours           = var.start_window_hours

  recovery_point_selection {
    algorithm             = var.recovery_point_algorithm
    include_vaults        = var.include_vaults
    exclude_vaults        = length(var.exclude_vaults) > 0 ? var.exclude_vaults : null
    recovery_point_types  = var.recovery_point_types
    selection_window_days = var.selection_window_days
  }

  tags = var.tags
}

resource "aws_backup_restore_testing_selection" "this" {
  name                      = "${local.plan_name}_rds"
  restore_testing_plan_name = aws_backup_restore_testing_plan.this.name
  protected_resource_type   = "RDS"
  iam_role_arn              = aws_iam_role.restore.arn
  protected_resource_arns   = local.select_by_tag ? ["*"] : var.protected_resource_arns
  validation_window_hours   = var.validation_window_hours

  dynamic "protected_resource_conditions" {
    for_each = local.select_by_tag ? [1] : []

    content {
      dynamic "string_equals" {
        for_each = var.protected_resource_tags

        content {
          key   = "aws:ResourceTag/${string_equals.key}"
          value = string_equals.value
        }
      }
    }
  }

  restore_metadata_overrides = local.restore_metadata_overrides

  lifecycle {
    precondition {
      condition     = (length(var.protected_resource_arns) > 0) != local.select_by_tag
      error_message = "Set exactly one of protected_resource_arns and protected_resource_tags."
    }

    precondition {
      condition     = length(var.sql_checks) == 0 || var.credentials_secret_arn != null
      error_message = "sql_checks need credentials_secret_arn."
    }
  }
}

# --- Network isolation ---------------------------------------------------------
# The restored instance is a copy of production data. It accepts connections
# from the validator only, and the validator can reach nothing else in the VPC.

resource "aws_security_group" "restored" {
  name        = "${var.name}-restored"
  description = "Restored test instance: reachable from the restore drill validator only"
  vpc_id      = var.vpc_id
  tags        = merge(var.tags, { Name = "${var.name}-restored" })
}

resource "aws_security_group" "validator" {
  name        = "${var.name}-validator"
  description = "Restore drill validator function"
  vpc_id      = var.vpc_id
  tags        = merge(var.tags, { Name = "${var.name}-validator" })
}

resource "aws_vpc_security_group_ingress_rule" "restored_from_validator" {
  security_group_id            = aws_security_group.restored.id
  description                  = "Database port from the validator"
  referenced_security_group_id = aws_security_group.validator.id
  ip_protocol                  = "tcp"
  from_port                    = var.db_port
  to_port                      = var.db_port
}

resource "aws_vpc_security_group_egress_rule" "validator_to_restored" {
  security_group_id            = aws_security_group.validator.id
  description                  = "Database port on the restored instance"
  referenced_security_group_id = aws_security_group.restored.id
  ip_protocol                  = "tcp"
  from_port                    = var.db_port
  to_port                      = var.db_port
}

resource "aws_vpc_security_group_egress_rule" "validator_to_aws_apis" {
  for_each = toset(var.validator_https_egress_cidrs)

  security_group_id = aws_security_group.validator.id
  description       = "HTTPS to AWS APIs"
  cidr_ipv4         = each.value
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
}

# --- Trigger ---------------------------------------------------------------------

resource "aws_cloudwatch_event_rule" "restore_job" {
  name        = "${var.name}-restore-job"
  description = "Restore jobs of the ${local.plan_name} restore testing plan that reached a final state"

  event_pattern = jsonencode({
    source      = ["aws.backup"]
    detail-type = ["Restore Job State Change"]
    detail = {
      restoreTestingPlanArn = [aws_backup_restore_testing_plan.this.arn]
      status                = ["COMPLETED", "FAILED", "ABORTED"]
    }
  })

  tags = var.tags
}

resource "aws_cloudwatch_event_target" "validator" {
  rule = aws_cloudwatch_event_rule.restore_job.name
  arn  = aws_lambda_function.validator.arn
}

resource "aws_lambda_permission" "events" {
  statement_id  = "AllowRestoreJobEvents"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.validator.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.restore_job.arn
}
