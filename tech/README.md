# Technology notes for azure-secretless-app

This folder teaches every technology the repository uses, starting from zero, through the repository's own files. You do not need to know any of them first. Each note says what the technology is, why this repository uses it, where it appears, how it works underneath, and then walks through this repository's own lines, quoting them and explaining each one. Code blocks in the walkthroughs are copied from the real files, and the output under each "Try it yourself" command was captured by running that command in this repository.

The repository is a small Azure web app that reads a secret from Key Vault and writes files to Blob Storage with a managed identity and no stored secret, and the Terraform that builds the Azure side of it.

Documentation formats (Markdown and Mermaid in the README and ARCHITECTURE files) have no note of their own: they hold prose and diagrams, and no code runs from them.

Every file follows the same nine headings: what it is, why this repository uses it, where it appears, how it works underneath, a walkthrough of this repository's own files, things to try, common mistakes, five questions with answers, and the official documentation.

The walkthrough of each note has two parts. The first explains the key ideas with chosen quotes. The second, under the heading "Every line, in order", quotes every non-blank line of every code and configuration file that note is responsible for, in blocks with their line numbers, and explains each block. Ideas such as a process, a port, an environment variable, a transaction or a certificate are explained the first time a block needs them.

## The files

| File | Its role in this repository |
|---|---|
| [`python.md`](python.md) | The language of the application and of its tests. |
| [`flask.md`](flask.md) | The web framework that turns HTTP requests into calls of the application's use cases. |
| [`gunicorn.md`](gunicorn.md) | The production web server that runs the Flask app inside the container. |
| [`azure-identity.md`](azure-identity.md) | The library that gets Azure access tokens with no stored secret. |
| [`azure-keyvault-secrets.md`](azure-keyvault-secrets.md) | The client the app uses to read the partner key from Key Vault. |
| [`azure-storage-blob.md`](azure-storage-blob.md) | The client the app uses to write uploaded files to a container. |
| [`pytest.md`](pytest.md) | Runs the tests and measures how much code they run. |
| [`ruff.md`](ruff.md) | Checks and formats the Python code on every `make lint`. |
| [`mypy.md`](mypy.md) | Checks the type hints across the source and the tests. |
| [`import-linter.md`](import-linter.md) | Fails the build when a layer imports something it must not. |
| [`pip-uv-and-lock-files.md`](pip-uv-and-lock-files.md) | How the exact set of Python packages is installed and pinned. |
| [`pyproject-toml.md`](pyproject-toml.md) | The one configuration file of the Python project. |
| [`editorconfig.md`](editorconfig.md) | Keeps whitespace consistent across editors. |
| [`json.md`](json.md) | The format of the app's answers and of its log lines. |
| [`git.md`](git.md) | Records the history and keeps local state out of it. |
| [`bash.md`](bash.md) | The scripts under `scripts/` that run the lesson against Azure. |
| [`shellcheck.md`](shellcheck.md) | Lints every script on `make lint`. |
| [`curl-and-jq.md`](curl-and-jq.md) | Call the deployed app and inspect Azure's JSON in the scripts. |
| [`make.md`](make.md) | The one command per job: `make test`, `make lint`, `make up`. |
| [`docker.md`](docker.md) | Packages the app as a small image that runs as a non-root user. |
| [`terraform.md`](terraform.md) | Defines every Azure resource of the lesson as code. |
| [`terraform-providers.md`](terraform-providers.md) | The plugins that create Azure resources and random names. |
| [`tflint.md`](tflint.md) | Lints the Terraform on `make lint`. |
| [`checkov.md`](checkov.md) | Scans the Terraform, Dockerfile and workflow for security misconfigurations. |
| [`github-actions.md`](github-actions.md) | Runs the same checks on every push. |
| [`yaml.md`](yaml.md) | The format of the CI workflow and the checkov settings. |
| [`azure-cli.md`](azure-cli.md) | The commands the scripts use to sign in, set the secret, build the image and read the logs. |
| [`azure-managed-identity-rbac.md`](azure-managed-identity-rbac.md) | How the app proves who it is and what it may do. |
| [`azure-key-vault.md`](azure-key-vault.md) | Holds the partner API key the app reads. |
| [`azure-storage.md`](azure-storage.md) | Holds the uploaded files. |
| [`azure-container-apps.md`](azure-container-apps.md) | Runs the app image with the managed identity attached. |
| [`azure-container-registry.md`](azure-container-registry.md) | Stores the app image and lets the pull identity fetch it. |
| [`azure-monitor-log-analytics.md`](azure-monitor-log-analytics.md) | Where the denials are read. |
| [`azure-resources-and-budgets.md`](azure-resources-and-budgets.md) | The scope of the lesson: one group, one budget. |

## Reading order

1. [Python](python.md)
2. [pyproject.toml and TOML](pyproject-toml.md)
3. [pip, uv, virtual environments and lock files](pip-uv-and-lock-files.md)
4. [Flask](flask.md)
5. [gunicorn](gunicorn.md)
6. [azure-identity (and azure-core)](azure-identity.md)
7. [azure-keyvault-secrets](azure-keyvault-secrets.md)
8. [azure-storage-blob](azure-storage-blob.md)
9. [JSON](json.md)
10. [pytest and coverage](pytest.md)
11. [ruff](ruff.md)
12. [mypy](mypy.md)
13. [import-linter](import-linter.md)
14. [.editorconfig](editorconfig.md)
15. [Git and .gitignore](git.md)
16. [Bash](bash.md)
17. [ShellCheck](shellcheck.md)
18. [curl and jq](curl-and-jq.md)
19. [GNU Make](make.md)
20. [Docker and the Dockerfile](docker.md)
21. [YAML](yaml.md)
22. [GitHub Actions](github-actions.md)
23. [Azure CLI](azure-cli.md)
24. [Resource groups, tags, providers and the budget](azure-resources-and-budgets.md)
25. [Managed identity and Azure RBAC](azure-managed-identity-rbac.md)
26. [Azure Key Vault](azure-key-vault.md)
27. [Azure Storage account and Blob container](azure-storage.md)
28. [Azure Container Registry](azure-container-registry.md)
29. [Azure Container Apps](azure-container-apps.md)
30. [Log Analytics and diagnostic settings](azure-monitor-log-analytics.md)
31. [Terraform](terraform.md)
32. [The azurerm and random providers](terraform-providers.md)
33. [TFLint](tflint.md)
34. [Checkov](checkov.md)

## If you have ten minutes

Read these three, in this order:

- [Managed identity and Azure RBAC](azure-managed-identity-rbac.md)
- [azure-identity (and azure-core)](azure-identity.md)
- [Terraform](terraform.md)

## Where every file is explained, line by line

Every code and configuration file of the repository is explained line by line in exactly one of the notes (the section "Every line, in order"). Files that are not listed here are documentation (Markdown), the license, generated lock files (the format is explained in the notes on lock files), or an example environment file that is described by its purpose only.

| File | Non-blank lines | Explained in |
|---|---|---|
| `.checkov.yaml` | 14 | [checkov.md](checkov.md) |
| `.dockerignore` | 17 | [docker.md](docker.md) |
| `.editorconfig` | 14 | [editorconfig.md](editorconfig.md) |
| `.github/workflows/ci.yml` | 41 | [github-actions.md](github-actions.md) |
| `.gitignore` | 26 | [git.md](git.md) |
| `.tflint.hcl` | 13 | [tflint.md](tflint.md) |
| `Dockerfile` | 21 | [docker.md](docker.md) |
| `Makefile` | 78 | [make.md](make.md) |
| `infra/environments/dev/backend.hcl.example` | 7 | [terraform.md](terraform.md) |
| `infra/environments/dev/main.tf` | 152 | [terraform.md](terraform.md) |
| `infra/environments/dev/outputs.tf` | 68 | [terraform.md](terraform.md) |
| `infra/environments/dev/providers.tf` | 17 | [terraform-providers.md](terraform-providers.md) |
| `infra/environments/dev/terraform.tfvars.example` | 15 | [terraform.md](terraform.md) |
| `infra/environments/dev/tests/dev.tftest.hcl` | 168 | [terraform.md](terraform.md) |
| `infra/environments/dev/variables.tf` | 92 | [terraform.md](terraform.md) |
| `infra/environments/dev/versions.tf` | 16 | [terraform-providers.md](terraform-providers.md) |
| `infra/modules/budget/main.tf` | 19 | [azure-resources-and-budgets.md](azure-resources-and-budgets.md) |
| `infra/modules/budget/outputs.tf` | 4 | [terraform.md](terraform.md) |
| `infra/modules/budget/tests/budget.tftest.hcl` | 29 | [terraform.md](terraform.md) |
| `infra/modules/budget/variables.tf` | 41 | [terraform.md](terraform.md) |
| `infra/modules/budget/versions.tf` | 9 | [terraform.md](terraform.md) |
| `infra/modules/container_app/main.tf` | 66 | [azure-container-apps.md](azure-container-apps.md) |
| `infra/modules/container_app/outputs.tf` | 12 | [terraform.md](terraform.md) |
| `infra/modules/container_app/tests/container_app.tftest.hcl` | 75 | [terraform.md](terraform.md) |
| `infra/modules/container_app/variables.tf` | 93 | [terraform.md](terraform.md) |
| `infra/modules/container_app/versions.tf` | 9 | [terraform.md](terraform.md) |
| `infra/modules/container_registry/main.tf` | 18 | [azure-container-registry.md](azure-container-registry.md) |
| `infra/modules/container_registry/outputs.tf` | 12 | [terraform.md](terraform.md) |
| `infra/modules/container_registry/tests/container_registry.tftest.hcl` | 20 | [terraform.md](terraform.md) |
| `infra/modules/container_registry/variables.tf` | 30 | [terraform.md](terraform.md) |
| `infra/modules/container_registry/versions.tf` | 9 | [terraform.md](terraform.md) |
| `infra/modules/key_vault/main.tf` | 27 | [azure-key-vault.md](azure-key-vault.md) |
| `infra/modules/key_vault/outputs.tf` | 12 | [terraform.md](terraform.md) |
| `infra/modules/key_vault/tests/key_vault.tftest.hcl` | 50 | [terraform.md](terraform.md) |
| `infra/modules/key_vault/variables.tf` | 52 | [terraform.md](terraform.md) |
| `infra/modules/key_vault/versions.tf` | 9 | [terraform.md](terraform.md) |
| `infra/modules/log_analytics/main.tf` | 8 | [azure-monitor-log-analytics.md](azure-monitor-log-analytics.md) |
| `infra/modules/log_analytics/outputs.tf` | 12 | [terraform.md](terraform.md) |
| `infra/modules/log_analytics/tests/log_analytics.tftest.hcl` | 20 | [terraform.md](terraform.md) |
| `infra/modules/log_analytics/variables.tf` | 26 | [terraform.md](terraform.md) |
| `infra/modules/log_analytics/versions.tf` | 9 | [terraform.md](terraform.md) |
| `infra/modules/role_assignments/main.tf` | 9 | [azure-managed-identity-rbac.md](azure-managed-identity-rbac.md) |
| `infra/modules/role_assignments/outputs.tf` | 10 | [terraform.md](terraform.md) |
| `infra/modules/role_assignments/tests/role_assignments.tftest.hcl` | 74 | [terraform.md](terraform.md) |
| `infra/modules/role_assignments/variables.tf` | 31 | [terraform.md](terraform.md) |
| `infra/modules/role_assignments/versions.tf` | 9 | [terraform.md](terraform.md) |
| `infra/modules/storage_uploads/main.tf` | 54 | [azure-storage.md](azure-storage.md) |
| `infra/modules/storage_uploads/outputs.tf` | 20 | [terraform.md](terraform.md) |
| `infra/modules/storage_uploads/tests/storage_uploads.tftest.hcl` | 50 | [terraform.md](terraform.md) |
| `infra/modules/storage_uploads/variables.tf` | 52 | [terraform.md](terraform.md) |
| `infra/modules/storage_uploads/versions.tf` | 9 | [terraform.md](terraform.md) |
| `infra/modules/user_assigned_identity/main.tf` | 6 | [azure-managed-identity-rbac.md](azure-managed-identity-rbac.md) |
| `infra/modules/user_assigned_identity/outputs.tf` | 16 | [terraform.md](terraform.md) |
| `infra/modules/user_assigned_identity/tests/user_assigned_identity.tftest.hcl` | 14 | [terraform.md](terraform.md) |
| `infra/modules/user_assigned_identity/variables.tf` | 17 | [terraform.md](terraform.md) |
| `infra/modules/user_assigned_identity/versions.tf` | 9 | [terraform.md](terraform.md) |
| `pyproject.toml` | 83 | [pyproject-toml.md](pyproject-toml.md) |
| `scripts/audit-config.sh` | 23 | [bash.md](bash.md) |
| `scripts/break-and-measure.sh` | 50 | [bash.md](bash.md) |
| `scripts/build-and-deploy.sh` | 27 | [bash.md](bash.md) |
| `scripts/docker-smoke.sh` | 23 | [bash.md](bash.md) |
| `scripts/lib.sh` | 31 | [bash.md](bash.md) |
| `scripts/prove-key-access-closed.sh` | 12 | [bash.md](bash.md) |
| `scripts/provision.sh` | 34 | [bash.md](bash.md) |
| `scripts/read-denials.sh` | 29 | [bash.md](bash.md) |
| `scripts/seed-secret.sh` | 13 | [bash.md](bash.md) |
| `scripts/smoke.sh` | 23 | [bash.md](bash.md) |
| `scripts/teardown.sh` | 26 | [bash.md](bash.md) |
| `src/secretless_app/__init__.py` | 1 | [python.md](python.md) |
| `src/secretless_app/application/__init__.py` | 1 | [python.md](python.md) |
| `src/secretless_app/application/check_health.py` | 12 | [python.md](python.md) |
| `src/secretless_app/application/ports.py` | 14 | [python.md](python.md) |
| `src/secretless_app/application/save_upload.py` | 17 | [python.md](python.md) |
| `src/secretless_app/application/services.py` | 9 | [python.md](python.md) |
| `src/secretless_app/domain/__init__.py` | 1 | [python.md](python.md) |
| `src/secretless_app/domain/blob_name.py` | 16 | [python.md](python.md) |
| `src/secretless_app/domain/errors.py` | 20 | [python.md](python.md) |
| `src/secretless_app/domain/health.py` | 6 | [python.md](python.md) |
| `src/secretless_app/domain/secret.py` | 17 | [python.md](python.md) |
| `src/secretless_app/infrastructure/__init__.py` | 1 | [python.md](python.md) |
| `src/secretless_app/infrastructure/azure_adapters.py` | 43 | [azure-keyvault-secrets.md](azure-keyvault-secrets.md) |
| `src/secretless_app/infrastructure/azure_errors.py` | 35 | [python.md](python.md) |
| `src/secretless_app/infrastructure/logging.py` | 29 | [python.md](python.md) |
| `src/secretless_app/infrastructure/memory_adapters.py` | 38 | [python.md](python.md) |
| `src/secretless_app/infrastructure/settings.py` | 65 | [python.md](python.md) |
| `src/secretless_app/infrastructure/wiring.py` | 25 | [python.md](python.md) |
| `src/secretless_app/interfaces/__init__.py` | 1 | [python.md](python.md) |
| `src/secretless_app/interfaces/http.py` | 77 | [flask.md](flask.md) |
| `src/secretless_app/interfaces/wsgi.py` | 12 | [gunicorn.md](gunicorn.md) |
| `tests/conftest.py` | 15 | [pytest.md](pytest.md) |
| `tests/e2e/test_server.py` | 87 | [pytest.md](pytest.md) |
| `tests/integration/test_azure_live.py` | 25 | [pytest.md](pytest.md) |
| `tests/unit/application/test_use_cases.py` | 45 | [pytest.md](pytest.md) |
| `tests/unit/domain/test_blob_name_and_secret.py` | 22 | [pytest.md](pytest.md) |
| `tests/unit/infrastructure/test_azure_adapters.py` | 54 | [pytest.md](pytest.md) |
| `tests/unit/infrastructure/test_azure_errors.py` | 65 | [pytest.md](pytest.md) |
| `tests/unit/infrastructure/test_logging_and_wiring.py` | 41 | [pytest.md](pytest.md) |
| `tests/unit/infrastructure/test_settings.py` | 37 | [pytest.md](pytest.md) |
| `tests/unit/interfaces/test_http.py` | 74 | [pytest.md](pytest.md) |
