# Plan-only tests against a mocked AWS provider. They need no AWS account and
# no credentials, so they run on every pull request.

mock_provider "aws" {
  mock_data "aws_partition" {
    defaults = {
      partition = "aws"
    }
  }

  mock_data "aws_region" {
    defaults = {
      region = "eu-central-1"
    }
  }

  mock_data "aws_caller_identity" {
    defaults = {
      account_id = "123456789012"
    }
  }
}

variables {
  name                         = "orders-drill"
  vpc_id                       = "vpc-0123456789abcdef0"
  restore_db_subnet_group_name = "restore-test"
  validator_subnet_ids         = ["subnet-0123456789abcdef0"]
  protected_resource_arns      = ["arn:aws:rds:eu-central-1:123456789012:db:orders"]
}

run "defaults" {
  command = plan

  assert {
    condition     = aws_backup_restore_testing_plan.this.name == "orders_drill"
    error_message = "Hyphens in the name must become underscores in the plan name."
  }

  assert {
    condition     = aws_backup_restore_testing_selection.this.protected_resource_type == "RDS"
    error_message = "The selection must target RDS."
  }

  assert {
    condition     = length(aws_backup_restore_testing_selection.this.protected_resource_arns) == 1 && contains(aws_backup_restore_testing_selection.this.protected_resource_arns, "arn:aws:rds:eu-central-1:123456789012:db:orders")
    error_message = "The selection must contain exactly the ARNs that were passed in."
  }

  assert {
    condition     = aws_lambda_function_event_invoke_config.validator.maximum_retry_attempts == 0
    error_message = "The validator must not be retried: a verdict can be set only once."
  }

  assert {
    condition     = aws_lambda_function.validator.environment[0].variables["SQL_CHECKS"] == "[]"
    error_message = "Without sql_checks the validator must receive an empty list."
  }

  assert {
    condition     = aws_vpc_security_group_ingress_rule.restored_from_validator.from_port == 5432
    error_message = "The restored instance must accept the database port only."
  }
}

run "restored_copy_stays_isolated" {
  command = plan

  variables {
    restore_instance_class = "db.t4g.micro"
    restore_metadata_overrides = {
      dbSubnetGroupName  = "somewhere-public"
      publiclyAccessible = "true"
    }
  }

  assert {
    condition     = aws_backup_restore_testing_selection.this.restore_metadata_overrides["dbSubnetGroupName"] == "restore-test"
    error_message = "A caller must not be able to override the subnet group of the restored copy."
  }

  assert {
    condition     = aws_backup_restore_testing_selection.this.restore_metadata_overrides["dbInstanceClass"] == "db.t4g.micro"
    error_message = "restore_instance_class must be passed as the dbInstanceClass override."
  }

  assert {
    condition     = aws_backup_restore_testing_selection.this.restore_metadata_overrides["publiclyAccessible"] == "true"
    error_message = "Overrides that the module does not own must pass through unchanged."
  }
}

run "select_by_tag" {
  command = plan

  variables {
    protected_resource_arns = []
    protected_resource_tags = {
      restore-drill = "true"
    }
  }

  assert {
    condition     = length(aws_backup_restore_testing_selection.this.protected_resource_arns) == 1 && contains(aws_backup_restore_testing_selection.this.protected_resource_arns, "*")
    error_message = "Tag selection needs the wildcard ARN."
  }

  assert {
    condition     = one(one(aws_backup_restore_testing_selection.this.protected_resource_conditions).string_equals).key == "aws:ResourceTag/restore-drill"
    error_message = "Tags must be turned into aws:ResourceTag conditions."
  }
}

run "sql_checks_reach_the_validator" {
  command = plan

  variables {
    db_name                = "orders"
    credentials_secret_arn = "arn:aws:secretsmanager:eu-central-1:123456789012:secret:orders-db-AbCdEf"
    sns_topic_arn          = "arn:aws:sns:eu-central-1:123456789012:alerts"
    sql_checks = [
      {
        name      = "orders exist"
        query     = "select count(*) from orders"
        min_value = 1000
      },
      {
        name          = "newest order"
        query         = "select max(created_at) from orders"
        max_age_hours = 26
      },
    ]
  }

  assert {
    condition     = length(jsondecode(aws_lambda_function.validator.environment[0].variables["SQL_CHECKS"])) == 2
    error_message = "Both checks must be passed to the validator."
  }

  assert {
    condition     = jsondecode(aws_lambda_function.validator.environment[0].variables["SQL_CHECKS"])[1].max_age_hours == 26
    error_message = "max_age_hours must reach the validator unchanged."
  }

  assert {
    condition     = strcontains(aws_iam_role_policy.validator.policy, "secretsmanager:GetSecretValue")
    error_message = "The validator needs read access to the credentials secret."
  }

  assert {
    condition     = strcontains(aws_iam_role_policy.validator.policy, "sns:Publish")
    error_message = "The validator needs permission to publish to the topic."
  }

  assert {
    condition     = one(one(aws_lambda_function_event_invoke_config.validator.destination_config).on_failure).destination == "arn:aws:sns:eu-central-1:123456789012:alerts"
    error_message = "A validator run that crashes must be sent to the SNS topic."
  }
}

run "no_secret_access_without_sql_checks" {
  command = plan

  assert {
    condition     = !strcontains(aws_iam_role_policy.validator.policy, "secretsmanager:GetSecretValue")
    error_message = "Without a credentials secret the validator must not get Secrets Manager access."
  }
}

run "rejects_arns_and_tags_together" {
  command = plan

  variables {
    protected_resource_tags = {
      restore-drill = "true"
    }
  }

  expect_failures = [
    aws_backup_restore_testing_selection.this,
  ]
}

run "rejects_no_selection" {
  command = plan

  variables {
    protected_resource_arns = []
  }

  expect_failures = [
    aws_backup_restore_testing_selection.this,
  ]
}

run "rejects_sql_checks_without_credentials" {
  command = plan

  variables {
    sql_checks = [
      {
        name  = "orders exist"
        query = "select count(*) from orders"
      },
    ]
  }

  expect_failures = [
    aws_backup_restore_testing_selection.this,
  ]
}

run "rejects_invalid_name" {
  command = plan

  variables {
    name = "Orders_Drill"
  }

  expect_failures = [
    var.name,
  ]
}

run "rejects_unknown_engine" {
  command = plan

  variables {
    engine = "oracle"
  }

  expect_failures = [
    var.engine,
  ]
}
