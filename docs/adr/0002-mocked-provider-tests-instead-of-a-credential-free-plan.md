# 2. Test the Terraform with a mocked provider

Status: accepted, 2026-10-27.

## Context

The task for this repository is to validate the infrastructure locally without credentials. `terraform validate` checks syntax and schema only. A `terraform plan` with the `azurerm` provider authenticates when the provider configures, even for resources that do not exist yet; a trial with dummy service principal values failed at token acquisition.

## Decision

Use `terraform test` with `mock_provider "azurerm"` for every module and for the environment. Module tests assert the security properties of each resource (shared key off, RBAC on, no admin user, no secret blocks) and the input validations (`expect_failures`). The environment test applies the composition against the mock and asserts the role assignments of each identity.

## Consequences

- `make validate` runs a real plan and apply of the whole composition in seconds, with no network.
- The tests prove the composition and the guards. They cannot prove that Azure accepts a value (a name already taken, a quota, a region without Container Apps); the first `terraform apply` is the check for that.
- Mock data for computed ids must look like real Azure ids so the scope validations run on them; the environment test supplies them.
- A real `terraform plan` is still available after `az login` (`terraform -chdir=infra/environments/dev plan`).
