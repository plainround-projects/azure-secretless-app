# Azure CLI

*The commands the scripts use to sign in, set the secret, build the image and read the logs. Pinned here: Azure CLI 2.84.0.*

## What it is

The Azure CLI (`az`) is a command-line program for working with Azure. `az login` signs you in. After that commands such as `az group exists` or `az keyvault secret set` call Azure's management and data APIs for you and print the result as text, a table or JSON.

## Why this repository uses it

Terraform creates the resources, but the lesson's data-plane steps (set the secret, list blobs, read the logs, remove a role) are `az` commands. The scripts are exact copies of what you would type.

## Where it appears

| File | What it does with it |
|---|---|
| `scripts/provision.sh` | `az provider register`, `az account show`, `az ad signed-in-user show`. |
| `scripts/seed-secret.sh` | `az keyvault secret set`. |
| `scripts/prove-key-access-closed.sh` | `az storage container list --auth-mode key`. |
| `scripts/build-and-deploy.sh` | `az acr build`, `az acr login`. |
| `scripts/smoke.sh` | `az role assignment list`, `az storage blob list`. |
| `scripts/audit-config.sh` | `az containerapp show`. |
| `scripts/break-and-measure.sh` | `az role assignment delete` and `create`. |
| `scripts/read-denials.sh` | `az monitor log-analytics query`. |
| `scripts/teardown.sh` | `az group exists`, `az keyvault list-deleted`, `az keyvault purge`. |

## How it works underneath

`az` is a Python program. Commands are grouped by service (`az keyvault`, `az network`) and each takes `--name value` options. `--query` takes a **JMESPath** expression to pick fields out of the JSON result; `--output tsv` prints plain values and `--output table` a table. `az login` stores tokens on your machine; commands then use them. `DefaultAzureCredential` in the app code can borrow that sign-in, which is why the same code runs on a laptop and in Azure.

Two kinds of call exist. **Management plane** calls (create a vault) go to Azure Resource Manager and are authorized by roles such as Contributor. **Data plane** calls (read a secret, list blobs) go to the service itself and need data roles. Being Owner of a resource group does not let you read secrets.

Role assignments and other changes take time to spread, so scripts retry data-plane calls that fail with 403 right after a role was granted.

## Walkthrough of this repository's use

```bash
require_login() {
  need az
  az account show >/dev/null 2>&1 || die "not signed in: run 'az login' first"
}
```

`az account show` prints the current subscription and fails if you are not signed in; the script uses only its exit code.

```bash
subscription_id       = "$(az account show --query id --output tsv)"
tenant_id             = "$(az account show --query tenantId --output tsv)"
deployer_object_id    = "$(az ad signed-in-user show --query id --output tsv)"
budget_contact_emails = ["$BUDGET_EMAIL"]
```

`--query id --output tsv` selects one field and prints it bare. `az ad signed-in-user show --query id` is your object id, which Terraform needs to grant you the two data roles.

```bash
retry 12 30 az keyvault secret set --vault-name "$VAULT" --name partner-api-key --value "$VALUE" --output none
```

Sets the secret. `--output none` prints nothing. The value never goes through Terraform.

```bash
az role assignment list --assignee "$PRINCIPAL" --all --query '[].{role:roleDefinitionName, scope:scope}' --output table
COUNT="$(az role assignment list --assignee "$PRINCIPAL" --all --query 'length(@)' --output tsv)"
[[ "$COUNT" == "2" ]] || die "expected 2 role assignments, found $COUNT"
```

`--assignee` takes the identity's **principal id**; `--all` includes assignments at every scope; the `--query` with `[].{role:..., scope:...}` builds a two-column table; `length(@)` counts the rows, so the script can insist on exactly two.

```bash
az role assignment delete --assignee "$PRINCIPAL" --role "$ROLE" --scope "$SCOPE"
wait_for "removal to first refused request" refused

log "restoring the role"
```

Removes one role at one scope, then re-creates it with `--assignee-principal-type ServicePrincipal` (this avoids a directory lookup right after the identity was created).

```bash
az monitor log-analytics query --workspace "$WORKSPACE" --analytics-query "$QUERY" --output table
```

Runs a KQL query in the workspace identified by its customer id.

## Try it yourself

Check the version.

```bash
az version --query '"azure-cli"' -o tsv
```

You should see something like this:

```text
2.84.0
```

Read the built-in help of a command used by the scripts.

```bash
az keyvault secret set --help 2>&1 | sed -n 1,6p
```

You should see something like this:

```text
Command
    az keyvault secret set : Create a secret (if one doesn't exist) or update a secret in a
    KeyVault.

Arguments
```

Without a login this tells you to sign in; with one it prints the subscription.

```bash
az account show 2>&1 | head -2
```

You should see something like this:

```text
ERROR: Please run 'az login' to setup account.
```

## Mistakes people make

- Forgetting `az login`, or being in the wrong subscription (`az account show`).
- Using `--auth-mode key` on a storage account that has shared keys disabled.
- Assuming Owner can read secrets. It cannot; a data role is needed.
- Treating a 403 right after a role assignment as permanent. It can take minutes.
- Parsing table output in scripts. Use `--query` with `--output tsv`.

## Check yourself

1. **What does `--query` take?**
   Answer: A JMESPath expression that selects fields from the JSON result.

2. **What is the difference between management plane and data plane?**
   Answer: Management plane creates and configures resources; data plane reads and writes the data inside them.

3. **Why can an Owner not read a Key Vault secret?**
   Answer: Owner is a management role; reading secrets needs a data role.

4. **What does `az login` do?**
   Answer: Signs you in and stores tokens that later commands use.

5. **How do scripts cope with slow role propagation?**
   Answer: They retry the failing data-plane call for a few minutes.

## Further reading

- Azure CLI 2.84: https://learn.microsoft.com/en-us/cli/azure/
- Query output: https://learn.microsoft.com/en-us/cli/azure/query-azure-cli
