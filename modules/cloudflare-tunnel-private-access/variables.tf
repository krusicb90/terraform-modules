variable "account_id" {
  description = "Cloudflare account ID."
  type        = string

  validation {
    condition     = can(regex("^[0-9a-f]{32}$", var.account_id))
    error_message = "account_id must be a 32-character hexadecimal Cloudflare account ID."
  }
}

variable "zone_id" {
  description = "ID of the Cloudflare zone that holds the hostnames."
  type        = string

  validation {
    condition     = can(regex("^[0-9a-f]{32}$", var.zone_id))
    error_message = "zone_id must be a 32-character hexadecimal Cloudflare zone ID."
  }
}

variable "team_name" {
  description = "Zero Trust team name: the first part of <team>.cloudflareaccess.com. cloudflared uses it to verify Access tokens at the origin."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]*$", var.team_name))
    error_message = "team_name must be the team name only, for example \"acme\", not a URL."
  }
}

variable "name" {
  description = "Name of the tunnel, also used as a prefix for the Access applications and the policy."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,38}[a-z0-9]$", var.name))
    error_message = "name must be 3-40 characters: lowercase letters, digits and hyphens, starting with a letter."
  }
}

variable "services" {
  description = <<-EOT
    Services on the machine to publish through the tunnel, keyed by a short name.
      hostname                 - public hostname, inside the zone
      service                  - where cloudflared sends the traffic, for example http://localhost:8080 or ssh://localhost:22
      type                     - Access application type: self_hosted (default) or ssh
      verify_access_at_origin  - make cloudflared itself reject requests without a valid Access token (default true)
  EOT
  type = map(object({
    hostname                = string
    service                 = string
    type                    = optional(string, "self_hosted")
    verify_access_at_origin = optional(bool, true)
  }))

  validation {
    condition     = length(var.services) > 0
    error_message = "services must contain at least one service."
  }

  validation {
    condition     = alltrue([for s in values(var.services) : can(regex("^[a-z0-9]([a-z0-9-]*[a-z0-9])?(\\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)+$", s.hostname))])
    error_message = "Every hostname must be a plain lowercase hostname such as app.example.com: no scheme, path, port or wildcard."
  }

  validation {
    condition     = length(distinct([for s in values(var.services) : s.hostname])) == length(var.services)
    error_message = "Every service needs its own hostname."
  }

  validation {
    condition     = alltrue([for s in values(var.services) : can(regex("^(http|https|ssh|rdp|tcp)://[^/ ]+", s.service))])
    error_message = "Every service must start with http://, https://, ssh://, rdp:// or tcp://."
  }

  validation {
    condition     = alltrue([for s in values(var.services) : contains(["self_hosted", "ssh"], s.type)])
    error_message = "type must be self_hosted or ssh."
  }
}

variable "allowed_emails" {
  description = "Email addresses that may reach the services."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for e in var.allowed_emails : can(regex("^[^@ ]+@[^@ ]+\\.[^@ ]+$", e))])
    error_message = "allowed_emails must contain email addresses."
  }
}

variable "allowed_email_domains" {
  description = "Email domains whose users may reach the services, for example example.com."
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
