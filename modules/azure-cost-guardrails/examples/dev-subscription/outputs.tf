output "action_group_id" {
  description = "ID of the action group that receives the notifications."
  value       = module.cost_guardrails.action_group_id
}

output "policy_assignment_ids" {
  description = "IDs of the policy assignments."
  value       = module.cost_guardrails.policy_assignment_ids
}
