locals {
  host_expression = "http.host eq \"${var.hostname}\""

  # Legacy stacks such as IIS treat /Admin and /admin as the same path, and an
  # attacker will try both. Paths are compared in lower case on both sides.
  blocked_expression = length(var.blocked_paths) == 0 ? null : format(
    "(%s and (%s))",
    local.host_expression,
    join(" or ", [for path in var.blocked_paths : "starts_with(lower(http.request.uri.path), \"${lower(path)}\")"]),
  )

  rate_limit_expression = var.rate_limit == null ? null : format(
    "(%s and (%s))",
    local.host_expression,
    join(" or ", [for path in var.rate_limit.paths : "starts_with(lower(http.request.uri.path), \"${lower(path)}\")"]),
  )

  firewall_rules = concat(
    local.blocked_expression == null ? [] : [{
      ref         = "block_paths"
      description = "Paths nobody should reach on ${var.hostname}"
      expression  = local.blocked_expression
      action      = "block"
    }],
    [for index, rule in var.extra_firewall_rules : {
      ref         = "extra_${index}"
      description = rule.description
      expression  = rule.expression
      action      = rule.action
    }],
  )

  # Keyed by a slug so that reordering the list does not recreate applications.
  # Paths with the same slug are rejected by the variable validation. Grouping
  # keeps this expression valid while that error is reported.
  protected_by_slug = { for path in var.protected_paths : trim(replace(lower(path), "/[^a-z0-9]+/", "-"), "-") => path... }
  protected         = { for slug, paths in local.protected_by_slug : slug => paths[0] }
}

# --- Block at the edge ----------------------------------------------------------

resource "cloudflare_ruleset" "firewall" {
  count = length(local.firewall_rules) > 0 ? 1 : 0

  zone_id     = var.zone_id
  name        = "${var.name}-firewall"
  description = "Custom firewall rules for ${var.hostname}, managed by Terraform"
  kind        = "zone"
  phase       = "http_request_firewall_custom"
  rules       = local.firewall_rules
}

resource "cloudflare_ruleset" "rate_limit" {
  count = var.rate_limit == null ? 0 : 1

  zone_id     = var.zone_id
  name        = "${var.name}-rate-limit"
  description = "Rate limiting for ${var.hostname}, managed by Terraform"
  kind        = "zone"
  phase       = "http_ratelimit"

  rules = [{
    ref         = "rate_limit_paths"
    description = "Too many requests from one client on ${var.hostname}"
    expression  = local.rate_limit_expression
    action      = "block"

    ratelimit = {
      characteristics     = ["cf.colo.id", "ip.src"]
      period              = var.rate_limit.period
      requests_per_period = var.rate_limit.requests_per_period
      mitigation_timeout  = var.rate_limit.mitigation_timeout
    }
  }]
}

# --- Require a login ---------------------------------------------------------------

resource "cloudflare_zero_trust_access_policy" "allow" {
  count = length(var.protected_paths) > 0 ? 1 : 0

  account_id       = var.account_id
  name             = "${var.name}-allow"
  decision         = "allow"
  session_duration = var.session_duration

  include = concat(
    [for email in var.allowed_emails : { email = { email = email } }],
    [for domain in var.allowed_email_domains : { email_domain = { domain = domain } }],
  )

  lifecycle {
    precondition {
      condition     = length(var.allowed_emails) + length(var.allowed_email_domains) > 0
      error_message = "protected_paths need allowed_emails or allowed_email_domains. A policy without identities would lock everyone out."
    }
  }
}

resource "cloudflare_zero_trust_access_application" "protected" {
  for_each = local.protected

  account_id       = var.account_id
  name             = "${var.name}-${each.key}"
  type             = "self_hosted"
  domain           = "${var.hostname}${each.value}"
  session_duration = var.session_duration

  policies = [{
    id         = cloudflare_zero_trust_access_policy.allow[0].id
    precedence = 1
  }]
}
