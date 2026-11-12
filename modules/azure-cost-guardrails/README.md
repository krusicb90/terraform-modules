# azure-cost-guardrails

Find out about cloud spend before the invoice does.

Most cloud bills grow for ordinary reasons: a test environment nobody switched
off, a VM size chosen in a hurry, a resource group nobody remembers creating.
None of it is hard to fix. It is hard to notice. This module puts the noticing
in place for an Azure subscription: who is told, when, and what is prevented
outright.

## What it does

1. **Budgets with a forecast warning.** A monthly budget for the subscription
   and for single resource groups. Notifications go out when actual spend
   passes a threshold, and when the forecast says it will.
2. **An anomaly alert.** An email when daily spend changes in a way Azure does
   not expect.
3. **Ownership tags.** Every resource group must carry the tags that say who
   owns it and who pays for it.
4. **A limit on VM sizes** in the resource groups you choose, such as a
   sandbox.
5. **An evening shutdown** for virtual machines that do not need to run
   overnight, with a warning beforehand.

Every part is optional, and all of it is native Azure: budgets, Cost
Management alerts, built-in Azure Policy definitions and VM shutdown
schedules. There is no function to maintain and nothing to pay for.

## Usage

```hcl
module "cost_guardrails" {
  source = "git::https://github.com/krusicb90/terraform-modules.git//modules/azure-cost-guardrails?ref=<commit or tag>"

  name                = "dev-guardrails"
  subscription_id     = "00000000-0000-0000-0000-000000000000"
  resource_group_name = "rg-monitoring"
  contact_emails      = ["platform@example.com"]
  budget_start_date   = "2026-01-01T00:00:00Z"

  subscription_budget = 2000

  resource_group_budgets = {
    team-a = {
      resource_group_id = azurerm_resource_group.team_a.id
      amount            = 600
    }
  }

  vm_size_limits = {
    sandbox = {
      resource_group_id = azurerm_resource_group.sandbox.id
      allowed_sizes     = ["Standard_B2s", "Standard_B2ms"]
    }
  }

  vm_shutdown = {
    build-agent = {
      virtual_machine_id = azurerm_linux_virtual_machine.build_agent.id
      location           = "westeurope"
    }
  }
}
```

A complete configuration is in [examples/dev-subscription](examples/dev-subscription).

## Requirements

- An existing resource group for the action group.
- Permission to create budgets and policy assignments on the subscription:
  Cost Management Contributor and Resource Policy Contributor, or Owner.
- Terraform 1.7 or newer, AzureRM provider 4.x.

## Design decisions

**A forecast threshold, not only actual spend.** A notification at 100% of
actual spend says the money is gone. A notification when the forecast reaches
100% arrives in the middle of the month, when something can still be switched
off. The defaults send both.

**Policies report before they deny.** `enforce_policies` is `false` by
default. On a subscription that already has resources, a policy that denies
from the first minute breaks someone's deployment and gets the whole thing
removed. The assignments start by showing what is not compliant. Set
`enforce_policies = true` when that list is empty.

**Built-in policies, not custom ones.** The module assigns the definitions
Microsoft maintains: "Require a tag on resource groups" and "Allowed virtual
machine size SKUs". There is no policy JSON in this repository to keep up to
date.

**Tags on resource groups.** Requiring tags on every resource blocks
deployments that people cannot easily fix, such as resources created by a
managed service. A resource group has an owner or it does not. That is the
level at which a bill can be questioned.

**The start date is an input.** Azure wants a budget to start on the first of
a month. A date computed at plan time would change every run and show a
difference forever. One explicit value is less convenient and stays stable.

**Shutdown comes with a warning.** The contact emails get a message before the
shutdown, with a link to postpone it. A shutdown that surprises someone in the
middle of a long job is switched off the next day.

**Notifications need a recipient.** The module refuses to plan without at
least one contact email.

## What budgets do not do

A budget does not stop spending. Azure sends a notification and keeps running
everything. Cost data also arrives with a delay of hours, so a budget is a
warning, not a brake. The parts of this module that prevent spend are the
policies and the shutdown schedule.

## Scope

- One subscription per module call.
- Budgets are monthly.
- The shutdown schedule covers virtual machines. It stops them and does not
  start them again in the morning.
- Required tags apply to resource groups.

## Inputs

| Name | Description | Type | Default |
|------|-------------|------|---------|
| `name` | Name used as a prefix for every resource. | `string` | required |
| `subscription_id` | ID of the subscription to guard, as a GUID. | `string` | required |
| `resource_group_name` | Existing resource group that holds the action group. | `string` | required |
| `contact_emails` | Email addresses that receive every budget and anomaly notification. | `list(string)` | required |
| `subscription_budget` | Monthly budget for the whole subscription, in the billing currency. Leave null for none. | `number` | `null` |
| `resource_group_budgets` | Monthly budgets for single resource groups, keyed by a short name. Use them for the groups whose owners should hear about their own spend. | `map(object)` | `{}` |
| `budget_start_date` | First day of the first budget month, as YYYY-MM-01T00:00:00Z. Azure requires the first of a month. It is an input because a computed date would change on every plan. | `string` | required |
| `actual_thresholds` | Percentages of the budget at which a notification is sent for actual spend. | `list(number)` | `[80, 100]` |
| `forecast_thresholds` | Percentages of the budget at which a notification is sent for forecasted spend. A forecast warns while there is still time to act. | `list(number)` | `[100]` |
| `anomaly_alert_enabled` | Send an email when Azure detects an unusual change in daily spend for the subscription. | `bool` | `true` |
| `required_tags` | Tags every resource group must have, so that spend can be traced to an owner. Assigned with the built-in policy 'Require a tag on resource groups'. | `list(string)` | `["owner", "cost-center"]` |
| `vm_size_limits` | Resource groups in which only the listed VM sizes may be created, keyed by a short name. Assigned with the built-in policy 'Allowed virtual machine size SKUs'. | `map(object)` | `{}` |
| `enforce_policies` | Deny deployments that violate the policies. When false, the policies only report compliance. Start with false on a subscription that already has resources. | `bool` | `false` |
| `vm_shutdown` | Daily shutdown for virtual machines that do not need to run overnight, keyed by a short name. Each entry needs `virtual_machine_id` and `location`. | `map(object)` | `{}` |
| `vm_shutdown_time` | Time of the daily shutdown, as HHmm in vm_shutdown_timezone. | `string` | `"1900"` |
| `vm_shutdown_timezone` | Windows time zone name for vm_shutdown_time, for example Central European Standard Time. | `string` | `"UTC"` |
| `vm_shutdown_notice_minutes` | Minutes before the shutdown at which the contact emails are warned (15-120). The warning has a link to postpone the shutdown. | `number` | `30` |
| `tags` | Tags added to every resource that supports them. | `map(string)` | `{}` |

## Outputs

| Name | Description |
|------|-------------|
| `action_group_id` | ID of the action group that receives the budget notifications. Add it to other alerts to reach the same people. |
| `subscription_budget_id` | ID of the subscription budget. Null when subscription_budget is not set. |
| `resource_group_budget_ids` | ID of each resource group budget, by key. |
| `anomaly_alert_id` | ID of the cost anomaly alert. Null when it is disabled. |
| `policy_assignment_ids` | IDs of the policy assignments, by kind and key. |
| `shutdown_schedule_ids` | ID of each shutdown schedule, by key. |

## Tests

```sh
terraform init -backend=false && terraform test   # mocked provider, no Azure subscription
```
