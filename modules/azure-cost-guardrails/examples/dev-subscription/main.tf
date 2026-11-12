# Guardrails for a development subscription.
#
# A monthly budget with a forecast warning, a budget per team resource group,
# an anomaly alert, required ownership tags, a limit on VM sizes in the sandbox
# and an evening shutdown for a build agent.

terraform {
  required_version = ">= 1.7.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 4.0.0, < 5.0.0"
    }
  }
}

provider "azurerm" {
  features {}
  subscription_id = var.subscription_id
}

module "cost_guardrails" {
  source = "../../"

  name                = "dev-guardrails"
  subscription_id     = var.subscription_id
  resource_group_name = var.monitoring_resource_group_name
  contact_emails      = var.contact_emails
  budget_start_date   = "2026-01-01T00:00:00Z"

  subscription_budget = 2000

  resource_group_budgets = {
    team-a = {
      resource_group_id = var.team_a_resource_group_id
      amount            = 600
    }
  }

  # Report first. Switch to true once the compliance view is clean.
  enforce_policies = false
  required_tags    = ["owner", "cost-center"]

  vm_size_limits = {
    sandbox = {
      resource_group_id = var.sandbox_resource_group_id
      allowed_sizes     = ["Standard_B2s", "Standard_B2ms", "Standard_D2s_v5"]
    }
  }

  vm_shutdown_time     = "1900"
  vm_shutdown_timezone = "Central European Standard Time"
  vm_shutdown = {
    build-agent = {
      virtual_machine_id = var.build_agent_vm_id
      location           = var.location
    }
  }

  tags = {
    purpose = "cost-guardrails"
  }
}
