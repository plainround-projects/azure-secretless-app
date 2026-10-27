# azure-secretless-app

A small web app on Azure Container Apps that reads an API key from Key Vault and writes uploaded files to Blob Storage as a user-assigned managed identity, with no connection string, account key or client secret anywhere, and every role assigned at the narrowest scope that works. The infrastructure is Terraform; the app is a layered, typed Python service whose tests run without Azure.

**Lesson realized:** `/prep/azure/project-secretless-app` (`data-structure-explainer/src/content/tracks/azure/11-project-secretless-app.md` in the Plainround app), "The secretless app you build" (Azure track, project 1). The lesson plans **5 hours**.
**Author:** Sumit Srivastava. **License:** MIT.

Nothing here has been deployed: the Azure subscription does not exist yet. Everything that can be checked without one has been (see [What was verified](#what-was-verified-without-a-subscription)); the rest is a list of commands in `scripts/` that you run once the subscription exists.

## Prerequisites

| Tool | Version | Why |
|---|---|---|
| Python | 3.12 or newer (3.13 used) | the app and its tests |
| Terraform | 1.9 or newer (1.17 used) | the infrastructure |
| Azure CLI | 2.60 or newer (2.84 used) | the runbook scripts |
| Docker | any recent | `make docker-smoke`, and the local build fallback |
| `uv` or `checkov` | checkov 3.3.30 | `make scan` (`uvx` runs it without installing) |
| `tflint` | 0.59 or newer | `make lint` runs it when it is installed (CI always does) |
| `jq`, `curl`, `shellcheck` | any | the scripts |
| An Azure subscription | needed only for the deploy section | none of the offline commands touch Azure |

## Setup, run, test, stop

Offline (no Azure, works on a Mac as written):

```bash
make install        # creates .venv from the hash-pinned requirements-dev.lock
make test           # 63 unit and end-to-end tests with coverage; domain and application must stay at 95% or more
make lint           # ruff, ruff format, mypy --strict, import-linter, terraform fmt, tflint
make validate       # terraform init -backend=false, validate, then terraform test for every module and the environment
make scan           # checkov over infra/, the Dockerfile and the workflow
make docker-smoke   # builds the image, runs it as a non-root user, calls it, stops it with SIGTERM
make run            # serves http://127.0.0.1:8000 with in-memory stand-ins for Key Vault and Storage
```

In a second terminal, the lesson's curl session against the local app:

```bash
curl -s http://127.0.0.1:8000/health                       # {"key_length":14,"status":"ok"}
curl -s -X POST --data-binary 'hello' http://127.0.0.1:8000/upload/hello.txt   # {"saved":"hello.txt"}
```

Rehearse step 5 without a subscription: `make run-denied` starts the app with the blob role "removed"; the upload answers `502` with `AuthorizationPermissionMismatch` and the log line carries the code and the detail.

Stop: `Ctrl+C` for `make run`; `make clean` removes `.venv` and the caches.

`make help` lists every target. `make check` is `lint`, `test` and `validate` together; the CI workflow runs it, plus `make audit` (pip-audit on the locked dependencies) and `make scan`.

## Deploy to Azure

Run this once the subscription exists. Nothing is billed until `make up`.

**Cost.** Estimates from Azure's published prices as I know them in October 2026; confirm in the pricing calculator before you rely on them. Left running for the five practice hours, the whole slice costs well under one US dollar. Left up for a month it costs about five US dollars, nearly all of it the Basic container registry (about 0.17 dollars a day).

| Resource | Billing | Idle cost |
|---|---|---|
| Container Apps (consumption, 0.25 vCPU, scale to zero) | per second of use, with a monthly free grant | about 0 |
| Key Vault (standard) | per 10,000 operations | cents |
| Storage account (LRS, hot) | per GB-month plus operations | cents |
| Container Registry (Basic) | per day | about 0.17 dollars a day |
| Log Analytics (PerGB2018) | per GB ingested, first 5 GB a month free | about 0 |
| Managed identities, role assignments, budget | free | 0 |

**Commands**, in the lesson's order. Each script is idempotent and prints what it does.

```bash
az login
export BUDGET_EMAIL=you@example.com            # step 1: the budget alert goes here

make up                                         # steps 1 to 3: scripts/provision.sh
                                                #   registers the resource providers, writes terraform.tfvars from your az session,
                                                #   terraform apply (group, workspace, identities, vault, storage, registry, roles, budget),
                                                #   sets the partner-api-key secret, proves --auth-mode key is refused
make deploy                                     # step 4: build the image in the registry, add the container app, wait for /live
make smoke                                      # steps 3 and 4: exactly two role assignments, /health, an upload, the blob list
make audit-config                               # step 4: no credential-shaped value in the deployed settings or in the source

scripts/break-and-measure.sh blob               # step 5: remove the blob role, time the first 502, restore, time the recovery
scripts/read-denials.sh blob                    #         the denial in the logs, with the caller's object id
scripts/break-and-measure.sh vault              #         the same for the Key Vault role
scripts/read-denials.sh vault

make down                                       # step 6: terraform destroy, then the soft-deleted vault and what to do with it
```

On a subscription where ACR Tasks is not allowed (some free-trial subscriptions), use `BUILD_MODE=local make deploy`; it builds with your local Docker and pushes.

**Teardown.** `make down` runs `terraform destroy` (this also removes the subscription-scoped budget, which deleting the group would not), prints `az group exists`, lists the soft-deleted vault with its purge date and says whether it can be purged. Check the Azure portal for leftovers named `kv-secretless-*`, `stsecretless*`, `acrsecretless*`.

## Done when: the lesson's checklist and the proof for each line

"Offline" means proven by a command in this repository with no subscription. "Subscription" means a command that runs against Azure after `make up`.

| Lesson step and its Done when | Offline proof | Subscription proof |
|---|---|---|
| **1. Set up the scope.** The budget exists and the workspace is ready to receive logs. | `terraform test` in `infra/modules/budget` (alerts at 80 and 100 percent, first-of-month rule, recipients required) and `log_analytics` | `az consumption budget list`; `az monitor log-analytics workspace show --query provisioningState` prints `"Succeeded"` (shown by `make up`'s apply) |
| **2. Create the identity and the resources.** A storage account key request fails because shared key access is off. | `terraform test` in `infra/modules/storage_uploads`: `shared_access_key_enabled == false`, public blobs off, TLS 1.2, private container; vault test: RBAC on | `scripts/prove-key-access-closed.sh` (run by `make up`) asserts `az storage container list --auth-mode key` fails with `KeyBasedAuthenticationNotPermitted` |
| **3. Grant narrow roles.** The identity's role assignments list exactly two entries, each on a single resource. | `terraform test` in `infra/environments/dev`: `the_app_identity_holds_exactly_two_roles_each_on_a_single_resource` (Key Vault Secrets User on the vault, Storage Blob Data Contributor on the container); `role_assignments` refuses a resource group, a subscription and Owner or Contributor | `make smoke` prints the table and fails unless the count is 2 |
| **4. Deploy the app with no secrets.** An upload lands in the container, and a search of the configuration and source finds no key, password or connection string. | `make test` (HTTP end-to-end through gunicorn); `container_app` test: no secret blocks, credential-shaped names and values refused; `make docker-smoke` | `make smoke` uploads and lists the blob; `make audit-config` searches the deployed container settings, the source, the lock file and the Dockerfile |
| **5. Break it and read the denial.** Both denials are in the logs, naming the identity and the missing permission; the time a role change took is noted. | `make run-denied`; unit tests assert `AuthorizationPermissionMismatch` and `ForbiddenByRbac` reach the log line with the SDK's message (which names the caller's object id) | `scripts/break-and-measure.sh blob\|vault` prints the removal-to-refusal and restore-to-recovery seconds; `scripts/read-denials.sh` runs the log queries. Record the numbers in the table in [docs/RUNBOOK.md](docs/RUNBOOK.md) |
| **6. Clean up.** The group is gone, and the soft-deleted vault and its name reservation have been checked. | none (nothing to delete offline) | `make down` |

| Lesson review checklist line | Where |
|---|---|
| A budget, a resource group and a workspace | step 1 above |
| A key request fails because shared key access is off | step 2 |
| Exactly two role assignments, each on one resource | step 3 |
| An upload lands; no key, password or connection string | step 4 |
| Both denials in the logs, with the identity and the missing action | step 5 |
| How long a role change took | step 5, recorded in RUNBOOK.md |
| Group deleted; soft delete and the vault name understood | step 6, and [ARCHITECTURE.md](ARCHITECTURE.md) failure modes |
| Why the app code is the same on a laptop and in Azure | `DefaultAzureCredential` in `infrastructure/azure_adapters.py`; ARCHITECTURE.md, decision 2 |

### What was verified without a subscription

Run on 2026-10-27 (see the repository history for the commands): `make lint`, `make test`, `make validate`, `make scan`, `make docker-smoke` where Docker was available, and the fresh-clone test. What these cannot show is Azure's own behavior: the real propagation time of a role change, the exact text of a live denial, the log table and column names in your workspace, and whether the regional quota allows Container Apps. The scripts and queries that depend on those were written from the lesson and the Azure CLI help and are the first thing to run when the subscription exists.

## Stretch goals

| Stretch | Built? |
|---|---|
| Replace the user-assigned identity with a system-assigned one and compare life cycles | No. The `container_app` module takes identity ids; switching is a few lines and the comparison is in [ARCHITECTURE.md](ARCHITECTURE.md), decision 1. |
| A private endpoint for the vault, with public network access off | No. It is the next Azure project, `azure-private-platform-slice`. The module already exposes `public_network_access_enabled`. |
| An alert on repeated authorization failures in the workspace | No. The queries in `scripts/read-denials.sh` are the starting point for a scheduled query rule. |

## What is simplified for teaching

- One environment (`dev`) with local Terraform state. `backend.hcl.example` shows the remote state setup a team would use.
- The vault and the storage account keep their public endpoints, because the operator's laptop seeds the secret and lists blobs. The firewall and private endpoints are the next project; the checkov skips on these resources say so.
- Purge protection is off by default (`purge_protection_enabled`), so a practice vault can be purged. Turn it on in production.
- The container registry is Basic, with no scanning or geo-replication (Premium features).
- The Container Apps environment is the default public one, not a virtual-network-integrated one.
- Live tests against Azure exist (`make test-azure`) but are skipped unless you ask, since they need the deployed resources.

## Project structure

```text
azure-secretless-app/
  src/secretless_app/
    domain/            names, secrets, errors; depends on nothing
    application/       the two use cases and their ports; depends on domain
    infrastructure/    Azure SDK adapters, in-memory adapters, settings, logging, composition root; depends on both
    interfaces/        the Flask app and the gunicorn entry point; depends on all, nothing depends on it
  tests/
    unit/              by layer, with in-memory fakes and an SDK stub
    e2e/               the real gunicorn server over HTTP (in-memory backend)
    integration/       the real adapters against deployed resources (skipped unless RUN_AZURE_TESTS=1)
  infra/
    modules/           one module per reusable piece, each with a README and tftest tests
      log_analytics/  user_assigned_identity/  key_vault/  storage_uploads/
      role_assignments/  container_registry/  container_app/  budget/
    environments/dev/  the composition: variables, providers, outputs, tfvars example, tests
  scripts/             the lesson's runbook as the commands you run once the subscription exists
  tech/                one note per technology the repository uses (34 files), taught from zero through this repository's own files; start at tech/README.md
  docs/                RUNBOOK.md and decision records (docs/adr)
  Dockerfile  Makefile  pyproject.toml  requirements*.lock  .tflint.hcl  .checkov.yaml  .github/workflows/ci.yml
```

The dependency rule (domain depends on nothing; application depends on domain; infrastructure on both; interfaces on all; nothing on interfaces) is enforced by `import-linter` in `make lint`; the Azure SDK, Flask and gunicorn are forbidden in domain and application, and the Azure SDK is forbidden in interfaces.

## Author and license

Sumit Srivastava. MIT, see [LICENSE](LICENSE).
