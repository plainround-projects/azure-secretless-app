# Resource groups, tags, providers and the budget

*The scope of the lesson: one group, one budget. Pinned here: azurerm_resource_group, azurerm_consumption_budget_subscription.*

## What it is

Azure organizes everything in a hierarchy. A **subscription** is the billing container. A **resource group** is a folder-like grouping of resources that share a life cycle: deleting the group deletes everything in it. **Tags** are name-value labels on resources. A **budget** is a spending limit on the subscription that sends emails when actual spend passes chosen percentages.

## Why this repository uses it

Step 1 of the lesson is the scope: a resource group to delete at the end and a budget so the practice cannot silently cost money.

## Where it appears

| File | What it does with it |
|---|---|
| `infra/environments/dev/main.tf` | The resource group, the tags and the budget module call. |
| `infra/modules/budget/` | The budget. |
| `scripts/provision.sh` | Registers the resource providers. |
| `scripts/teardown.sh` | Checks the group is gone. |

## How it works underneath

Resource names have rules (length, characters, global uniqueness for names that become host names). Each kind of resource belongs to a **resource provider** such as `Microsoft.KeyVault`; a provider must be **registered** in a subscription before you create its resources. Register once with `az provider register`.

A budget is a subscription-level resource, so deleting a resource group does not remove it. Azure requires its start date to be the first day of a month. Budget alerts are based on actual cost that Azure computes with a delay, so they warn; they do not stop spending.

## Walkthrough of this repository's use

```hcl
resource "azurerm_resource_group" "this" {
  name     = local.names.resource_group
  location = var.location
  tags     = local.tags
}
```

One group named `rg-secretless`, tagged with the project, environment, owner and `managed_by = "terraform"`.

```hcl
resource "azurerm_consumption_budget_subscription" "this" {
  name            = var.name
  subscription_id = "/subscriptions/${var.subscription_id}"
  amount          = var.amount
  time_grain      = "Monthly"

  time_period {
    start_date = var.start_date
  }

  dynamic "notification" {
    for_each = toset(var.thresholds_percent)
    content {
      enabled        = true
      threshold      = notification.value
      operator       = "GreaterThan"
      threshold_type = "Actual"
      contact_emails = var.contact_emails
    }
  }
}
```

A monthly budget with one notification per threshold (`dynamic "notification"` repeats the block for 80 and 100 percent). `threshold_type = "Actual"` is real spend, not forecast. `start_date` must be the first of a month.

```hcl
module "budget" {
  source = "../../modules/budget"
  count  = length(var.budget_contact_emails) > 0 ? 1 : 0

  name            = local.names.budget
  subscription_id = var.subscription_id
  amount          = var.budget_amount
  start_date      = coalesce(var.budget_start_date, "2026-01-01T00:00:00Z")
  contact_emails  = var.budget_contact_emails
}
```

`count = length(var.budget_contact_emails) > 0 ? 1 : 0`: no recipients, no budget.

## Try it yourself

Run the budget tests (thresholds, first-of-month rule).

```bash
cd infra/modules/budget && terraform init -backend=false -input=false >/dev/null && terraform test 2>&1 | tail -4
```

You should see something like this:

```text
tests/budget.tftest.hcl... tearing down
tests/budget.tftest.hcl... pass

Success! 3 passed, 0 failed.
```

See the standard tags.

```bash
grep -n 'tags' -B1 -A8 infra/environments/dev/main.tf | sed -n 1,14p
```

You should see something like this:

```text
22-
23:  tags = merge(
24-    {
25-      project     = "azure-secretless-app"
26-      environment = var.environment
27-      managed_by  = "terraform"
28-      owner       = "sumit-srivastava"
29-    },
30:    var.tags,
31-  )
32-
33-  # The one place that decides who may do what. Every scope is a single resource.
34-  app_assignments = {
35-    app_reads_secrets = {
```

## Mistakes people make

- Forgetting that deleting the resource group does not delete the subscription-level budget.
- A budget start date that is not the first of a month.
- Skipping provider registration on a new subscription.
- Unlabeled resources. Every resource here gets the same tags.
- Believing a budget caps spending; it only notifies.

## Check yourself

1. **What happens when you delete a resource group?**
   Answer: Every resource in it is deleted.

2. **Why register resource providers?**
   Answer: A subscription can create resources of a kind only after its provider is registered.

3. **What must a budget's start date be?**
   Answer: The first day of a month.

4. **Does a budget stop spending?**
   Answer: No; it sends alerts.

5. **What are tags for?**
   Answer: Labelling resources for ownership, cost and search.

## Further reading

- Resource groups: https://learn.microsoft.com/en-us/azure/azure-resource-manager/management/manage-resource-groups-portal
- Budgets: https://learn.microsoft.com/en-us/azure/cost-management-billing/costs/tutorial-acm-create-budgets
- Naming rules: https://learn.microsoft.com/en-us/azure/azure-resource-manager/management/resource-name-rules
