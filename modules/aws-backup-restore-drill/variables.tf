variable "name" {
  description = "Name used as a prefix for every resource. Lowercase letters, digits and hyphens."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,38}[a-z0-9]$", var.name))
    error_message = "name must be 3-40 characters: lowercase letters, digits and hyphens, starting with a letter."
  }
}

# --- What to restore ---------------------------------------------------------

variable "protected_resource_arns" {
  description = "ARNs of the RDS instances to restore-test (up to 30). Use this or protected_resource_tags, not both."
  type        = list(string)
  default     = []

  validation {
    condition     = length(var.protected_resource_arns) <= 30
    error_message = "A restore testing selection accepts at most 30 resource ARNs."
  }
}

variable "protected_resource_tags" {
  description = "Select RDS instances by tag instead of by ARN. Every tag must match. Use this or protected_resource_arns, not both."
  type        = map(string)
  default     = {}
}

# --- When to restore, and from which recovery point ---------------------------

variable "schedule_expression" {
  description = "Cron expression for the drill, in AWS Backup format."
  type        = string
  default     = "cron(0 3 ? * SUN *)"
}

variable "schedule_expression_timezone" {
  description = "Time zone of schedule_expression."
  type        = string
  default     = "Etc/UTC"
}

variable "start_window_hours" {
  description = "Hours after the scheduled time in which the restore job may start (1-168)."
  type        = number
  default     = 1

  validation {
    condition     = var.start_window_hours >= 1 && var.start_window_hours <= 168
    error_message = "start_window_hours must be between 1 and 168."
  }
}

variable "recovery_point_algorithm" {
  description = "Which recovery point to restore: LATEST_WITHIN_WINDOW or RANDOM_WITHIN_WINDOW."
  type        = string
  default     = "LATEST_WITHIN_WINDOW"

  validation {
    condition     = contains(["LATEST_WITHIN_WINDOW", "RANDOM_WITHIN_WINDOW"], var.recovery_point_algorithm)
    error_message = "recovery_point_algorithm must be LATEST_WITHIN_WINDOW or RANDOM_WITHIN_WINDOW."
  }
}

variable "recovery_point_types" {
  description = "Recovery point types to consider: SNAPSHOT, CONTINUOUS or both."
  type        = list(string)
  default     = ["SNAPSHOT"]

  validation {
    condition     = length(var.recovery_point_types) > 0 && alltrue([for t in var.recovery_point_types : contains(["SNAPSHOT", "CONTINUOUS"], t)])
    error_message = "recovery_point_types may contain only SNAPSHOT and CONTINUOUS, and must not be empty."
  }
}

variable "selection_window_days" {
  description = "How far back to look for a recovery point (1-365). Keep it longer than the backup interval, or the drill has nothing to restore."
  type        = number
  default     = 7

  validation {
    condition     = var.selection_window_days >= 1 && var.selection_window_days <= 365
    error_message = "selection_window_days must be between 1 and 365."
  }
}

variable "include_vaults" {
  description = "Backup vault ARNs to take recovery points from. The default takes them from every vault."
  type        = list(string)
  default     = ["*"]
}

variable "exclude_vaults" {
  description = "Backup vault ARNs to skip."
  type        = list(string)
  default     = []
}

variable "validation_window_hours" {
  description = "Hours the restored instance is kept for validation before AWS Backup deletes it (1-168). You pay for the instance during this window."
  type        = number
  default     = 1

  validation {
    condition     = var.validation_window_hours >= 1 && var.validation_window_hours <= 168
    error_message = "validation_window_hours must be between 1 and 168."
  }
}

# --- Where the restored copy lives ---------------------------------------------

variable "vpc_id" {
  description = "VPC in which the restored instance and the validator run."
  type        = string
}

variable "restore_db_subnet_group_name" {
  description = "DB subnet group for the restored instance. Use private subnets."
  type        = string
}

variable "validator_subnet_ids" {
  description = "Private subnets for the validator function. They need a route to the AWS APIs (NAT gateway or VPC endpoints)."
  type        = list(string)

  validation {
    condition     = length(var.validator_subnet_ids) > 0
    error_message = "validator_subnet_ids must contain at least one subnet."
  }
}

variable "validator_https_egress_cidrs" {
  description = "CIDR blocks the validator may reach on port 443 to call AWS APIs. Narrow this to your VPC endpoints if you use them."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "db_port" {
  description = "Port the database listens on."
  type        = number
  default     = 5432
}

variable "restore_instance_class" {
  description = "Instance class for the restored copy. Leave null to let AWS Backup infer it from the recovery point."
  type        = string
  default     = null
}

variable "restore_metadata_overrides" {
  description = "Extra restore metadata overrides. The subnet group and security group set by this module always win, so the restored copy stays isolated."
  type        = map(string)
  default     = {}
}

# --- What to check ---------------------------------------------------------------

variable "engine" {
  description = "Database engine, used for sql_checks: postgres or mysql."
  type        = string
  default     = "postgres"

  validation {
    condition     = contains(["postgres", "mysql"], var.engine)
    error_message = "engine must be postgres or mysql."
  }
}

variable "db_name" {
  description = "Database to connect to for sql_checks."
  type        = string
  default     = ""
}

variable "credentials_secret_arn" {
  description = "Secrets Manager secret with the JSON keys username and password, valid for the source database. Required for sql_checks."
  type        = string
  default     = null
}

variable "credentials_kms_key_arn" {
  description = "KMS key that encrypts the credentials secret, if it is a customer managed key."
  type        = string
  default     = null
}

variable "sql_checks" {
  description = <<-EOT
    Queries to run against the restored database. Each query must return at least one row.
    The first column of the first row is compared with:
      min_value      - fail if the number is lower (for example a row count)
      max_age_hours  - fail if the timestamp is older (for example the newest order)
    Queries run in a read-only session.
  EOT
  type = list(object({
    name          = string
    query         = string
    min_value     = optional(number)
    max_age_hours = optional(number)
  }))
  default = []
}

variable "db_ca_bundle_file" {
  description = "Path to a PEM file with the RDS certificate authority bundle. When set, the validator verifies the server certificate. When null, the connection is encrypted but not verified."
  type        = string
  default     = null
}

# --- Validator function -------------------------------------------------------------

variable "lambda_layer_arns" {
  description = "Lambda layers for the validator. sql_checks need a layer with pg8000 (postgres) or PyMySQL (mysql). See scripts/build-driver-layer.sh."
  type        = list(string)
  default     = []
}

variable "validator_timeout_seconds" {
  description = "Timeout of the validator function. It includes waiting for the restored instance to become available."
  type        = number
  default     = 300

  validation {
    condition     = var.validator_timeout_seconds >= 60 && var.validator_timeout_seconds <= 900
    error_message = "validator_timeout_seconds must be between 60 and 900."
  }
}

variable "validator_memory_mb" {
  description = "Memory of the validator function, in MB."
  type        = number
  default     = 256
}

variable "log_retention_days" {
  description = "Retention of the validator logs, in days. The logs are the record that a drill ran, so the default keeps a year."
  type        = number
  default     = 365
}

variable "kms_key_arn" {
  description = "Customer managed KMS key for the validator's logs and environment variables. Its key policy must allow CloudWatch Logs. Leave null to use AWS managed encryption."
  type        = string
  default     = null
}

# --- Reporting -----------------------------------------------------------------------

variable "sns_topic_arn" {
  description = "SNS topic for the drill result. Failed drills are always published, and so is a validator run that crashes or times out. Leave null to disable notifications."
  type        = string
  default     = null
}

variable "notify_on_success" {
  description = "Also publish successful drills to the SNS topic."
  type        = bool
  default     = false
}

variable "metric_namespace" {
  description = "CloudWatch namespace for the DrillSuccess and RestoreDurationSeconds metrics."
  type        = string
  default     = "RestoreDrill"
}

variable "tags" {
  description = "Tags added to every resource."
  type        = map(string)
  default     = {}
}
