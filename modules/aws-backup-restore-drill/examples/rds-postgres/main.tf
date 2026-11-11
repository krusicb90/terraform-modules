# Weekly restore drill for one PostgreSQL instance.
#
# Every Sunday at 03:00 the latest snapshot is restored into isolated subnets,
# two queries prove that the data is there and recent, and the on-call topic
# hears about it only if something is wrong.

terraform {
  required_version = ">= 1.7.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.0.0"
    }
  }
}

provider "aws" {
  region = var.region
}

module "restore_drill" {
  source = "../../"

  name = "orders-restore-drill"

  protected_resource_arns = [var.db_instance_arn]

  schedule_expression          = "cron(0 3 ? * SUN *)"
  schedule_expression_timezone = "Europe/Zagreb"
  selection_window_days        = 2

  vpc_id                       = var.vpc_id
  restore_db_subnet_group_name = var.restore_db_subnet_group_name
  validator_subnet_ids         = var.validator_subnet_ids
  restore_instance_class       = "db.t4g.medium"

  engine                 = "postgres"
  db_name                = "orders"
  credentials_secret_arn = var.credentials_secret_arn
  lambda_layer_arns      = [var.pg8000_layer_arn]

  sql_checks = [
    {
      name      = "orders exist"
      query     = "select count(*) from orders"
      min_value = 1000
    },
    {
      name          = "newest order is recent"
      query         = "select max(created_at) from orders"
      max_age_hours = 50
    },
  ]

  sns_topic_arn = var.alerts_topic_arn

  tags = {
    Service = "orders"
    Purpose = "restore-drill"
  }
}
