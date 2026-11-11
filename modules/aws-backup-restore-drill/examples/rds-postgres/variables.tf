variable "region" {
  description = "AWS region."
  type        = string
  default     = "eu-central-1"
}

variable "db_instance_arn" {
  description = "ARN of the RDS instance to restore-test. It must already be backed up by AWS Backup."
  type        = string
}

variable "vpc_id" {
  description = "VPC of the database."
  type        = string
}

variable "restore_db_subnet_group_name" {
  description = "DB subnet group for the restored copy."
  type        = string
}

variable "validator_subnet_ids" {
  description = "Private subnets for the validator function."
  type        = list(string)
}

variable "credentials_secret_arn" {
  description = "Secrets Manager secret with the database username and password."
  type        = string
}

variable "pg8000_layer_arn" {
  description = "Lambda layer with the pg8000 driver, built with scripts/build-driver-layer.sh."
  type        = string
}

variable "alerts_topic_arn" {
  description = "SNS topic that receives failed drills."
  type        = string
}
