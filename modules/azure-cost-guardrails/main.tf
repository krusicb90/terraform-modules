locals {
  subscription_resource_id = "/subscriptions/${var.subscription_id}"

  # Built-in Azure Policy definitions.
  policy_require_tag_on_resource_groups = "/providers/Microsoft.Authorization/policyDefinitions/96670d01-0a4d-4649-9c89-2d3abc0a5025"
  policy_allowed_vm_sizes               = "/providers/Microsoft.Authorization/policyDefinitions/cccc23c7-8427-4f53-ad12-b6a63eb452b3"

  # One notification per threshold. Forecast notifications fire while the money
  # is not spent yet, which is when a warning is still useful.
  notifications = concat(
    [for threshold in var.actual_thresholds : { threshold = threshold, type = "Actual" }],
    [for threshold in var.forecast_thresholds : { threshold = threshold, type = "Forecasted" }],
  )
}

# --- Who hears about it ----------------------------------------------------------

resource "azurerm_monitor_action_group" "cost" {
  name                = "${var.name}-cost"
  resource_group_name = var.resource_group_name
  short_name          = "cost"
  tags                = var.tags

  dynamic "email_receiver" {
    for_each = toset(var.contact_emails)

    content {
      name                    = replace(email_receiver.value, "/[^A-Za-z0-9]+/", "-")
      email_address           = email_receiver.value
      use_common_alert_schema = true
    }
  }
}

# --- Budgets ---------------------------------------------------------------------

resource "azurerm_consumption_budget_subscription" "this" {
  count = var.subscription_budget == null ? 0 : 1

  name            = "${var.name}-subscription"
  subscription_id = local.subscription_resource_id
  amount          = var.subscription_budget
  time_grain      = "Monthly"

  time_period {
    start_date = var.budget_start_date
  }

  dynamic "notification" {
    for_each = local.notifications

    content {
      enabled        = true
      operator       = "GreaterThanOrEqualTo"
      threshold      = notification.value.threshold
      threshold_type = notification.value.type
      contact_emails = var.contact_emails
      contact_groups = [azurerm_monitor_action_group.cost.id]
    }
  }
}

resource "azurerm_consumption_budget_resource_group" "this" {
  for_each = var.resource_group_budgets

  name              = "${var.name}-${each.key}"
  resource_group_id = each.value.resource_group_id
  amount            = each.value.amount
  time_grain        = "Monthly"

  time_period {
    start_date = var.budget_start_date
  }

  dynamic "notification" {
    for_each = local.notifications

    content {
      enabled        = true
      operator       = "GreaterThanOrEqualTo"
      threshold      = notification.value.threshold
      threshold_type = notification.value.type
      contact_emails = var.contact_emails
      contact_groups = [azurerm_monitor_action_group.cost.id]
    }
  }
}

# --- Anomalies ----------------------------------------------------------------------
# A budget catches slow overspend. An anomaly alert catches the sudden kind: a
# forgotten cluster, a loop that writes to storage, a wrong SKU.

resource "azurerm_cost_anomaly_alert" "this" {
  count = var.anomaly_alert_enabled ? 1 : 0

  name            = "${var.name}-anomaly"
  display_name    = "${var.name} cost anomaly"
  subscription_id = local.subscription_resource_id
  email_subject   = "Unusual Azure spend detected"
  email_addresses = var.contact_emails
}

# --- Policies ----------------------------------------------------------------------------

resource "azurerm_subscription_policy_assignment" "required_tag" {
  for_each = toset(var.required_tags)

  name                 = substr("${var.name}-tag-${each.value}", 0, 64)
  display_name         = "Resource groups must have the tag ${each.value}"
  description          = "Spend that has no owner cannot be questioned. Every resource group needs this tag."
  subscription_id      = local.subscription_resource_id
  policy_definition_id = local.policy_require_tag_on_resource_groups
  enforce              = var.enforce_policies

  parameters = jsonencode({
    tagName = { value = each.value }
  })

  non_compliance_message {
    content = "Add the tag '${each.value}' to the resource group."
  }
}

resource "azurerm_resource_group_policy_assignment" "vm_sizes" {
  for_each = var.vm_size_limits

  name                 = substr("${var.name}-vm-sizes-${each.key}", 0, 64)
  display_name         = "Only approved VM sizes"
  description          = "Limits virtual machine sizes in this resource group to the approved list."
  resource_group_id    = each.value.resource_group_id
  policy_definition_id = local.policy_allowed_vm_sizes
  enforce              = var.enforce_policies

  parameters = jsonencode({
    listOfAllowedSKUs = { value = each.value.allowed_sizes }
  })

  non_compliance_message {
    content = "This VM size is not approved here. Allowed sizes: ${join(", ", each.value.allowed_sizes)}."
  }
}

# --- Shutdown outside working hours -----------------------------------------------------

resource "azurerm_dev_test_global_vm_shutdown_schedule" "this" {
  for_each = var.vm_shutdown

  virtual_machine_id    = each.value.virtual_machine_id
  location              = each.value.location
  enabled               = true
  daily_recurrence_time = var.vm_shutdown_time
  timezone              = var.vm_shutdown_timezone
  tags                  = var.tags

  notification_settings {
    enabled         = true
    time_in_minutes = var.vm_shutdown_notice_minutes
    email           = join(";", var.contact_emails)
  }
}
