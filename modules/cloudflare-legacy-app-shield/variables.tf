variable "account_id" {
  description = "Cloudflare account ID."
  type        = string

  validation {
    condition     = can(regex("^[0-9a-f]{32}$", var.account_id))
    error_message = "account_id must be a 32-character hexadecimal Cloudflare account ID."
  }
}

variable "zone_id" {
  description = "ID of the Cloudflare zone that serves the application."
  type        = string

  validation {
    condition     = can(regex("^[0-9a-f]{32}$", var.zone_id))
    error_message = "zone_id must be a 32-character hexadecimal Cloudflare zone ID."
  }
}

variable "name" {
  description = "Name used as a prefix for the rulesets, the Access applications and the policy."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,38}[a-z0-9]$", var.name))
    error_message = "name must be 3-40 characters: lowercase letters, digits and hyphens, starting with a letter."
  }
}

variable "hostname" {
  description = "Public hostname of the application, proxied through Cloudflare. Every rule is scoped to it."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9]([a-z0-9-]*[a-z0-9])?(\\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)+$", var.hostname))
    error_message = "hostname must be a plain lowercase hostname such as www.example.com: no scheme, path, port or wildcard."
  }
}

# --- Paths that need a login ----------------------------------------------------

variable "protected_paths" {
  description = "Path prefixes that require a login through Cloudflare Access, for example /admin. Use it for the parts only staff should reach."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for p in var.protected_paths : can(regex("^/[A-Za-z0-9._~/-]+$", p))])
    error_message = "Every path must start with / and contain only letters, digits and the characters . _ ~ / -"
  }

  validation {
    condition     = length(distinct([for p in var.protected_paths : trim(replace(lower(p), "/[^a-z0-9]+/", "-"), "-")])) == length(var.protected_paths)
    error_message = "protected_paths must differ in more than case and punctuation: /Admin and /admin, or /a-b and /a/b, count as the same path."
  }
}

variable "allowed_emails" {
  description = "Email addresses that may reach the protected paths."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for e in var.allowed_emails : can(regex("^[^@ ]+@[^@ ]+\\.[^@ ]+$", e))])
    error_message = "allowed_emails must contain email addresses."
  }
}

variable "allowed_email_domains" {
  description = "Email domains whose users may reach the protected paths, for example example.com."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for d in var.allowed_email_domains : can(regex("^[a-z0-9]([a-z0-9-]*[a-z0-9])?(\\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)+$", d))])
    error_message = "allowed_email_domains must contain bare domains such as example.com, without @."
  }
}

variable "session_duration" {
  description = "How long a login stays valid before the user must authenticate again."
  type        = string
  default     = "8h"

  validation {
    condition     = can(regex("^([0-9]+(h|m|s))+$", var.session_duration))
    error_message = "session_duration must look like 8h, 30m or 2h45m."
  }
}

# --- Paths nobody should reach ---------------------------------------------------

variable "blocked_paths" {
  description = "Path prefixes that are blocked for everyone at the Cloudflare edge, for example an endpoint with a known vulnerability that the application does not need."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for p in var.blocked_paths : can(regex("^/[A-Za-z0-9._~/-]+$", p))])
    error_message = "Every path must start with / and contain only letters, digits and the characters . _ ~ / -"
  }
}

variable "extra_firewall_rules" {
  description = "More custom firewall rules for the zone. A zone has one custom ruleset, and this module owns it, so rules that exist outside the module belong here."
  type = list(object({
    description = string
    expression  = string
    action      = string
  }))
  default = []

  validation {
    condition     = alltrue([for r in var.extra_firewall_rules : contains(["block", "challenge", "js_challenge", "managed_challenge", "log"], r.action)])
    error_message = "action must be block, challenge, js_challenge, managed_challenge or log."
  }
}

# --- Paths that get hammered --------------------------------------------------------

variable "rate_limit" {
  description = <<-EOT
    Rate limit for path prefixes such as a login page. Requests are counted per client IP.
      paths                - path prefixes the limit applies to
      requests_per_period  - requests allowed per period before the client is blocked
      period               - counting period in seconds. The free plan accepts 10 only.
      mitigation_timeout   - how long the client stays blocked, in seconds. The free plan accepts 10 only.
    Leave null for no rate limit.
  EOT
  type = object({
    paths               = list(string)
    requests_per_period = number
    period              = optional(number, 10)
    mitigation_timeout  = optional(number, 10)
  })
  default = null

  validation {
    condition     = var.rate_limit == null ? true : length(var.rate_limit.paths) > 0 && alltrue([for p in var.rate_limit.paths : can(regex("^/[A-Za-z0-9._~/-]+$", p))])
    error_message = "rate_limit.paths needs at least one path. Every path must start with / and contain only letters, digits and the characters . _ ~ / -"
  }

  validation {
    condition     = var.rate_limit == null ? true : var.rate_limit.requests_per_period >= 1
    error_message = "rate_limit.requests_per_period must be at least 1."
  }
}
