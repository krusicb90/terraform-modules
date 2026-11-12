output "protected_urls" {
  description = "Everything that requires a login."
  value       = module.shield.protected_urls
}

output "blocked_expression" {
  description = "The expression that matches the blocked paths."
  value       = module.shield.blocked_expression
}
