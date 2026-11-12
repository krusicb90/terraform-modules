variable "name" {
  description = "Name used as a prefix for every resource."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,28}[a-z0-9]$", var.name))
    error_message = "name must be 3-30 characters: lowercase letters, digits and hyphens, starting with a letter."
  }
}

variable "subscription_id" {
  description = "ID of the subscription to guard, as a GUID."
  type        = string

  validation {
    condition     = can(regex("^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$", var.subscription_id))
    error_message = "subscription_id must be a lowercase GUID such as 00000000-0000-0000-0000-000000000000."
  }
}

variable "resource_group_name" {
  description = "Existing resource group that holds the action group."
  type        = string
}

variable "contact_emails" {
  description = "Email addresses that receive every budget and anomaly notification."
  type        = list(string)

  validation {
    condition     = length(var.contact_emails) > 0 && alltrue([for e in var.contact_emails : can(regex("^[^@ ]+@[^@ ]+\\.[^@ ]+$", e))])
    error_message = "contact_emails needs at least one email address. A guardrail that notifies nobody does nothing."
  }
}

# --- Budgets -------------------------------------------------------------------

variable "subscription_budget" {
  description = "Monthly budget for the whole subscription, in the billing currency. Leave null for none."
  type        = number
  default     = null

  validation {
    condition     = var.subscription_budget == null ? true : var.subscription_budget > 0
    error_message = "subscription_budget must be greater than zero."
  }
}

variable "resource_group_budgets" {
  description = "Monthly budgets for single resource groups, keyed by a short name. Use them for the groups whose owners should hear about their own spend."
  type = map(object({
    resource_group_id = string
    amount            = number
  }))
  default = {}

  validation {
    condition     = alltrue([for b in values(var.resource_group_budgets) : b.amount > 0])
    error_message = "Every budget amount must be greater than zero."
  }
}

variable "budget_start_date" {
  description = "First day of the first budget month, as YYYY-MM-01T00:00:00Z. Azure requires the first of a month. It is an input because a computed date would change on every plan."
  type        = string

  validation {
    condition     = can(regex("^[0-9]{4}-(0[1-9]|1[0-2])-01T00:00:00Z$", var.budget_start_date))
    error_message = "budget_start_date must be the first day of a month, for example 2026-01-01T00:00:00Z."
  }
}

variable "actual_thresholds" {
  description = "Percentages of the budget at which a notification is sent for actual spend."
  type        = list(number)
  default     = [80, 100]

  validation {
    condition     = length(var.actual_thresholds) > 0 && alltrue([for t in var.actual_thresholds : t > 0 && t <= 1000])
    error_message = "actual_thresholds needs at least one value, each between 0 and 1000."
  }
}

variable "forecast_thresholds" {
  description = "Percentages of the budget at which a notification is sent for forecasted spend. A forecast warns while there is still time to act."
  type        = list(number)
  default     = [100]

  validation {
    condition     = alltrue([for t in var.forecast_thresholds : t > 0 && t <= 1000])
    error_message = "forecast_thresholds must be between 0 and 1000."
  }
}

# --- Anomalies -----------------------------------------------------------------

variable "anomaly_alert_enabled" {
  description = "Send an email when Azure detects an unusual change in daily spend for the subscription."
  type        = bool
  default     = true
}

# --- Policies ---------------------------------------------------------------------

variable "required_tags" {
  description = "Tags every resource group must have, so that spend can be traced to an owner. Assigned with the built-in policy 'Require a tag on resource groups'."
  type        = list(string)
  default     = ["owner", "cost-center"]

  validation {
    condition     = alltrue([for t in var.required_tags : can(regex("^[A-Za-z0-9][A-Za-z0-9_.-]{0,62}$", t))])
    error_message = "Tag names may contain letters, digits, hyphens, underscores and dots."
  }
}

variable "vm_size_limits" {
  description = "Resource groups in which only the listed VM sizes may be created, keyed by a short name. Assigned with the built-in policy 'Allowed virtual machine size SKUs'."
  type = map(object({
    resource_group_id = string
    allowed_sizes     = list(string)
  }))
  default = {}

  validation {
    condition     = alltrue([for l in values(var.vm_size_limits) : length(l.allowed_sizes) > 0])
    error_message = "allowed_sizes must contain at least one VM size, or nothing could be created in that resource group."
  }
}

variable "enforce_policies" {
  description = "Deny deployments that violate the policies. When false, the policies only report compliance. Start with false on a subscription that already has resources."
  type        = bool
  default     = false
}

# --- Shutdown outside working hours ----------------------------------------------------

variable "vm_shutdown" {
  description = <<-EOT
    Daily shutdown for virtual machines that do not need to run overnight, keyed by a short name.
      virtual_machine_id  - resource ID of the virtual machine
      location            - region of the virtual machine
    The machines are shut down, not started again.
  EOT
  type = map(object({
    virtual_machine_id = string
    location           = string
  }))
  default = {}
}

variable "vm_shutdown_time" {
  description = "Time of the daily shutdown, as HHmm in vm_shutdown_timezone."
  type        = string
  default     = "1900"

  validation {
    condition     = can(regex("^([01][0-9]|2[0-3])[0-5][0-9]$", var.vm_shutdown_time))
    error_message = "vm_shutdown_time must be HHmm, for example 1900."
  }
}

variable "vm_shutdown_timezone" {
  description = "Windows time zone name for vm_shutdown_time, for example Central European Standard Time."
  type        = string
  default     = "UTC"
}

variable "vm_shutdown_notice_minutes" {
  description = "Minutes before the shutdown at which the contact emails are warned (15-120). The warning has a link to postpone the shutdown."
  type        = number
  default     = 30

  validation {
    condition     = var.vm_shutdown_notice_minutes >= 15 && var.vm_shutdown_notice_minutes <= 120
    error_message = "vm_shutdown_notice_minutes must be between 15 and 120."
  }
}

variable "tags" {
  description = "Tags added to every resource that supports them."
  type        = map(string)
  default     = {}
}
