output "restore_testing_plan_name" {
  description = "Name of the restore testing plan."
  value       = module.restore_drill.restore_testing_plan_name
}

output "validator_function_name" {
  description = "Name of the validator function. Its log group has the result of every drill."
  value       = module.restore_drill.validator_function_name
}
