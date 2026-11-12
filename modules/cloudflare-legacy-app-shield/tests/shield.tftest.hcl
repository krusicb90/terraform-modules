# Tests against a mocked Cloudflare provider. They need no Cloudflare account
# and create nothing, so they run on every push.

mock_provider "cloudflare" {}

variables {
  account_id            = "0123456789abcdef0123456789abcdef"
  zone_id               = "fedcba9876543210fedcba9876543210"
  name                  = "legacy-cms"
  hostname              = "www.example.com"
  protected_paths       = ["/admin", "/cms/editor"]
  allowed_email_domains = ["example.com"]
  blocked_paths         = ["/Reports/Export.ashx", "/upload/handler.axd"]
}

run "blocked_paths_become_one_rule" {
  command = plan

  assert {
    condition     = length(cloudflare_ruleset.firewall) == 1 && length(cloudflare_ruleset.firewall[0].rules) == 1
    error_message = "All blocked paths must fit in one rule, so the free plan's rule limit is not used up."
  }

  assert {
    condition     = cloudflare_ruleset.firewall[0].phase == "http_request_firewall_custom" && cloudflare_ruleset.firewall[0].kind == "zone"
    error_message = "The rules must go into the zone's custom firewall ruleset."
  }

  assert {
    condition     = cloudflare_ruleset.firewall[0].rules[0].action == "block"
    error_message = "Blocked paths must be blocked, not challenged."
  }

  assert {
    condition     = cloudflare_ruleset.firewall[0].rules[0].expression == "(http.host eq \"www.example.com\" and (starts_with(lower(http.request.uri.path), \"/reports/export.ashx\") or starts_with(lower(http.request.uri.path), \"/upload/handler.axd\")))"
    error_message = "The expression must be scoped to the hostname and compare paths in lower case."
  }
}

run "matching_ignores_case" {
  command = plan

  variables {
    blocked_paths = ["/Admin/Shell"]
  }

  assert {
    condition     = strcontains(output.blocked_expression, "lower(http.request.uri.path)") && strcontains(output.blocked_expression, "\"/admin/shell\"")
    error_message = "Both the request path and the configured path must be lowered, or /ADMIN/shell would get through."
  }
}

run "protected_paths_get_access_applications" {
  command = plan

  assert {
    condition     = length(cloudflare_zero_trust_access_application.protected) == 2
    error_message = "Every protected path needs its own Access application."
  }

  assert {
    condition     = cloudflare_zero_trust_access_application.protected["admin"].domain == "www.example.com/admin"
    error_message = "The Access application must cover the hostname and the path."
  }

  assert {
    condition     = cloudflare_zero_trust_access_application.protected["cms-editor"].domain == "www.example.com/cms/editor"
    error_message = "Nested paths must keep their full path."
  }

  assert {
    condition     = length(cloudflare_zero_trust_access_policy.allow[0].include) == 1 && cloudflare_zero_trust_access_policy.allow[0].decision == "allow"
    error_message = "The shared policy must be an allow-list with the identities that were passed in."
  }

  assert {
    condition     = output.protected_urls == ["www.example.com/admin", "www.example.com/cms/editor"]
    error_message = "protected_urls must list every protected path with its hostname."
  }
}

run "nothing_is_created_for_features_that_are_off" {
  command = plan

  variables {
    protected_paths       = []
    allowed_email_domains = []
    blocked_paths         = []
  }

  assert {
    condition     = length(cloudflare_ruleset.firewall) == 0 && length(cloudflare_ruleset.rate_limit) == 0
    error_message = "Without rules there must be no rulesets."
  }

  assert {
    condition     = length(cloudflare_zero_trust_access_application.protected) == 0 && length(cloudflare_zero_trust_access_policy.allow) == 0
    error_message = "Without protected paths there must be no Access resources."
  }

  assert {
    condition     = output.blocked_expression == null
    error_message = "Without blocked paths there is no expression."
  }
}

run "extra_rules_follow_the_block_rule" {
  command = plan

  variables {
    extra_firewall_rules = [
      {
        description = "Challenge clients with a high threat score"
        expression  = "(cf.threat_score gt 30)"
        action      = "managed_challenge"
      },
    ]
  }

  assert {
    condition     = length(cloudflare_ruleset.firewall[0].rules) == 2
    error_message = "Extra rules must be added to the same ruleset, because a zone has only one."
  }

  assert {
    condition     = cloudflare_ruleset.firewall[0].rules[0].ref == "block_paths" && cloudflare_ruleset.firewall[0].rules[1].action == "managed_challenge"
    error_message = "The block rule must be evaluated first."
  }
}

run "rate_limit_counts_per_client" {
  command = plan

  variables {
    rate_limit = {
      paths               = ["/Login"]
      requests_per_period = 20
    }
  }

  assert {
    condition     = cloudflare_ruleset.rate_limit[0].phase == "http_ratelimit"
    error_message = "The rate limit must go into the rate limiting phase."
  }

  assert {
    condition     = cloudflare_ruleset.rate_limit[0].rules[0].ratelimit.requests_per_period == 20 && cloudflare_ruleset.rate_limit[0].rules[0].ratelimit.period == 10 && cloudflare_ruleset.rate_limit[0].rules[0].ratelimit.mitigation_timeout == 10
    error_message = "The defaults must be the values the free plan accepts."
  }

  assert {
    condition     = contains(cloudflare_ruleset.rate_limit[0].rules[0].ratelimit.characteristics, "ip.src")
    error_message = "Requests must be counted per client IP."
  }

  assert {
    condition     = strcontains(cloudflare_ruleset.rate_limit[0].rules[0].expression, "\"/login\"")
    error_message = "Rate limit paths must be compared in lower case too."
  }
}

run "rejects_protected_paths_without_identities" {
  command = plan

  variables {
    allowed_email_domains = []
  }

  expect_failures = [
    cloudflare_zero_trust_access_policy.allow,
  ]
}

run "rejects_a_path_that_could_break_out_of_the_expression" {
  command = plan

  variables {
    blocked_paths = ["/admin\") or (true"]
  }

  expect_failures = [
    var.blocked_paths,
  ]
}

run "rejects_a_path_without_a_leading_slash" {
  command = plan

  variables {
    protected_paths = ["admin"]
  }

  expect_failures = [
    var.protected_paths,
  ]
}

run "rejects_paths_that_differ_only_in_case" {
  command = plan

  variables {
    protected_paths = ["/admin", "/Admin"]
  }

  expect_failures = [
    var.protected_paths,
  ]
}

run "rejects_a_hostname_with_a_scheme" {
  command = plan

  variables {
    hostname = "https://www.example.com"
  }

  expect_failures = [
    var.hostname,
  ]
}

run "rejects_an_empty_rate_limit" {
  command = plan

  variables {
    rate_limit = {
      paths               = []
      requests_per_period = 20
    }
  }

  expect_failures = [
    var.rate_limit,
  ]
}
