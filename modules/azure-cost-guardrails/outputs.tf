output "action_group_id" {
  description = "ID of the action group that receives the budget notifications. Add it to other alerts to reach the same people."
  value       = azurerm_monitor_action_group.cost.id
}

output "subscription_budget_id" {
  description = "ID of the subscription budget. Null when subscription_budget is not set."
  value       = one(azurerm_consumption_budget_subscription.this[*].id)
}

output "resource_group_budget_ids" {
  description = "ID of each resource group budget, by key."
  value       = { for key, budget in azurerm_consumption_budget_resource_group.this : key => budget.id }
}

output "anomaly_alert_id" {
  description = "ID of the cost anomaly alert. Null when it is disabled."
  value       = one(azurerm_cost_anomaly_alert.this[*].id)
}

output "policy_assignment_ids" {
  description = "IDs of the policy assignments, by kind and key."
  value = {
    required_tags = { for key, assignment in azurerm_subscription_policy_assignment.required_tag : key => assignment.id }
    vm_sizes      = { for key, assignment in azurerm_resource_group_policy_assignment.vm_sizes : key => assignment.id }
  }
}

output "shutdown_schedule_ids" {
  description = "ID of each shutdown schedule, by key."
  value       = { for key, schedule in azurerm_dev_test_global_vm_shutdown_schedule.this : key => schedule.id }
}
