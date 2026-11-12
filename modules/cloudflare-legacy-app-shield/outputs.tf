output "firewall_ruleset_id" {
  description = "ID of the custom firewall ruleset. Null when there are no blocked paths and no extra rules."
  value       = one(cloudflare_ruleset.firewall[*].id)
}

output "rate_limit_ruleset_id" {
  description = "ID of the rate limiting ruleset. Null when rate_limit is not set."
  value       = one(cloudflare_ruleset.rate_limit[*].id)
}

output "blocked_expression" {
  description = "The expression that matches the blocked paths. Paste it into the Cloudflare dashboard to test it against real traffic."
  value       = local.blocked_expression
}

output "protected_urls" {
  description = "The host and path of everything that requires a login."
  value       = [for path in var.protected_paths : "${var.hostname}${path}"]
}

output "access_application_ids" {
  description = "ID of the Access application of each protected path, by path slug."
  value       = { for key, application in cloudflare_zero_trust_access_application.protected : key => application.id }
}

output "access_policy_id" {
  description = "ID of the Access policy shared by the protected paths. Null when there are none."
  value       = one(cloudflare_zero_trust_access_policy.allow[*].id)
}
