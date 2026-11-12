# Tests against a mocked Azure provider. They need no subscription and create
# nothing, so they run on every push.

mock_provider "azurerm" {}

variables {
  name                = "dev-guardrails"
  subscription_id     = "00000000-1111-2222-3333-444444444444"
  resource_group_name = "rg-monitoring"
  contact_emails      = ["platform@example.com", "finance@example.com"]
  budget_start_date   = "2026-01-01T00:00:00Z"
  subscription_budget = 2000
}

run "subscription_budget_warns_before_and_after" {
  command = plan

  assert {
    condition     = azurerm_consumption_budget_subscription.this[0].subscription_id == "/subscriptions/00000000-1111-2222-3333-444444444444"
    error_message = "The budget must be scoped to the subscription that was passed in."
  }

  assert {
    condition     = azurerm_consumption_budget_subscription.this[0].amount == 2000 && azurerm_consumption_budget_subscription.this[0].time_grain == "Monthly"
    error_message = "The budget must be monthly, with the amount that was passed in."
  }

  assert {
    condition     = length(azurerm_consumption_budget_subscription.this[0].notification) == 3
    error_message = "The defaults must give three notifications: 80% and 100% actual, 100% forecasted."
  }

  assert {
    condition     = length([for n in azurerm_consumption_budget_subscription.this[0].notification : n if n.threshold_type == "Forecasted" && n.threshold == 100]) == 1
    error_message = "There must be a forecast notification, so the warning arrives before the money is spent."
  }

  assert {
    condition     = alltrue([for n in azurerm_consumption_budget_subscription.this[0].notification : length(n.contact_emails) == 2 && n.enabled])
    error_message = "Every notification must be enabled and reach every contact."
  }
}

run "everyone_is_notified_through_one_action_group" {
  command = plan

  assert {
    condition     = length(azurerm_monitor_action_group.cost.email_receiver) == 2
    error_message = "The action group needs one receiver per contact email."
  }

  assert {
    condition     = length(azurerm_cost_anomaly_alert.this) == 1 && length(azurerm_cost_anomaly_alert.this[0].email_addresses) == 2
    error_message = "The anomaly alert must be on by default and reach every contact."
  }
}

run "policies_report_before_they_deny" {
  command = plan

  assert {
    condition     = length(azurerm_subscription_policy_assignment.required_tag) == 2
    error_message = "The default required tags are owner and cost-center."
  }

  assert {
    condition     = alltrue([for a in azurerm_subscription_policy_assignment.required_tag : a.enforce == false])
    error_message = "Policies must not deny by default. On a subscription with existing resources that would break deployments."
  }

  assert {
    condition     = jsondecode(azurerm_subscription_policy_assignment.required_tag["owner"].parameters).tagName.value == "owner"
    error_message = "Each assignment must pass its tag name to the built-in policy."
  }

  assert {
    condition     = azurerm_subscription_policy_assignment.required_tag["owner"].policy_definition_id == "/providers/Microsoft.Authorization/policyDefinitions/96670d01-0a4d-4649-9c89-2d3abc0a5025"
    error_message = "Required tags must use the built-in policy 'Require a tag on resource groups'."
  }
}

run "policies_deny_when_enforced" {
  command = plan

  variables {
    enforce_policies = true
    vm_size_limits = {
      dev = {
        resource_group_id = "/subscriptions/00000000-1111-2222-3333-444444444444/resourceGroups/rg-dev"
        allowed_sizes     = ["Standard_B2s", "Standard_B2ms"]
      }
    }
  }

  assert {
    condition     = alltrue([for a in azurerm_subscription_policy_assignment.required_tag : a.enforce]) && azurerm_resource_group_policy_assignment.vm_sizes["dev"].enforce
    error_message = "enforce_policies must switch every assignment to deny."
  }

  assert {
    condition     = jsondecode(azurerm_resource_group_policy_assignment.vm_sizes["dev"].parameters).listOfAllowedSKUs.value == ["Standard_B2s", "Standard_B2ms"]
    error_message = "The allowed sizes must reach the built-in policy unchanged."
  }

  assert {
    condition     = azurerm_resource_group_policy_assignment.vm_sizes["dev"].policy_definition_id == "/providers/Microsoft.Authorization/policyDefinitions/cccc23c7-8427-4f53-ad12-b6a63eb452b3"
    error_message = "VM size limits must use the built-in policy 'Allowed virtual machine size SKUs'."
  }
}

run "resource_group_budgets_are_independent" {
  command = plan

  variables {
    subscription_budget = null
    forecast_thresholds = []
    resource_group_budgets = {
      team-a = {
        resource_group_id = "/subscriptions/00000000-1111-2222-3333-444444444444/resourceGroups/rg-team-a"
        amount            = 300
      }
      team-b = {
        resource_group_id = "/subscriptions/00000000-1111-2222-3333-444444444444/resourceGroups/rg-team-b"
        amount            = 150
      }
    }
  }

  assert {
    condition     = length(azurerm_consumption_budget_subscription.this) == 0
    error_message = "Without subscription_budget there must be no subscription budget."
  }

  assert {
    condition     = azurerm_consumption_budget_resource_group.this["team-a"].amount == 300 && azurerm_consumption_budget_resource_group.this["team-b"].amount == 150
    error_message = "Each resource group must get its own amount."
  }

  assert {
    condition     = length(azurerm_consumption_budget_resource_group.this["team-a"].notification) == 2
    error_message = "Without forecast thresholds only the actual-spend notifications remain."
  }
}

run "virtual_machines_shut_down_in_the_evening" {
  command = plan

  variables {
    vm_shutdown_time     = "1830"
    vm_shutdown_timezone = "Central European Standard Time"
    vm_shutdown = {
      build-agent = {
        virtual_machine_id = "/subscriptions/00000000-1111-2222-3333-444444444444/resourceGroups/rg-dev/providers/Microsoft.Compute/virtualMachines/build-agent"
        location           = "westeurope"
      }
    }
  }

  assert {
    condition     = azurerm_dev_test_global_vm_shutdown_schedule.this["build-agent"].daily_recurrence_time == "1830" && azurerm_dev_test_global_vm_shutdown_schedule.this["build-agent"].timezone == "Central European Standard Time"
    error_message = "The schedule must use the time and time zone that were passed in."
  }

  assert {
    condition     = azurerm_dev_test_global_vm_shutdown_schedule.this["build-agent"].notification_settings[0].enabled && azurerm_dev_test_global_vm_shutdown_schedule.this["build-agent"].notification_settings[0].time_in_minutes == 30
    error_message = "People must be warned before the shutdown, so they can postpone it."
  }
}

run "optional_parts_can_be_switched_off" {
  command = plan

  variables {
    subscription_budget   = null
    anomaly_alert_enabled = false
    required_tags         = []
  }

  assert {
    condition     = length(azurerm_consumption_budget_subscription.this) == 0 && length(azurerm_cost_anomaly_alert.this) == 0
    error_message = "Switched-off parts must create nothing."
  }

  assert {
    condition     = length(azurerm_subscription_policy_assignment.required_tag) == 0 && length(azurerm_dev_test_global_vm_shutdown_schedule.this) == 0
    error_message = "Without tags and virtual machines there must be no assignments and no schedules."
  }
}

run "rejects_guardrails_that_notify_nobody" {
  command = plan

  variables {
    contact_emails = []
  }

  expect_failures = [
    var.contact_emails,
  ]
}

run "rejects_a_start_date_that_is_not_the_first_of_a_month" {
  command = plan

  variables {
    budget_start_date = "2026-01-15T00:00:00Z"
  }

  expect_failures = [
    var.budget_start_date,
  ]
}

run "rejects_a_budget_of_zero" {
  command = plan

  variables {
    subscription_budget = 0
  }

  expect_failures = [
    var.subscription_budget,
  ]
}

run "rejects_a_subscription_resource_id" {
  command = plan

  variables {
    subscription_id = "/subscriptions/00000000-1111-2222-3333-444444444444"
  }

  expect_failures = [
    var.subscription_id,
  ]
}

run "rejects_a_size_limit_that_allows_nothing" {
  command = plan

  variables {
    vm_size_limits = {
      dev = {
        resource_group_id = "/subscriptions/00000000-1111-2222-3333-444444444444/resourceGroups/rg-dev"
        allowed_sizes     = []
      }
    }
  }

  expect_failures = [
    var.vm_size_limits,
  ]
}

run "rejects_an_invalid_shutdown_time" {
  command = plan

  variables {
    vm_shutdown_time = "7pm"
  }

  expect_failures = [
    var.vm_shutdown_time,
  ]
}
