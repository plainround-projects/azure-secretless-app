# Technology notes for azure-secretless-app

This folder teaches every technology the repository uses, starting from zero, through the repository's own files. You do not need to know any of them first. Each note says what the technology is, why this repository uses it, where it appears, how it works underneath, and then walks through this repository's own lines, quoting them and explaining each one. Code blocks in the walkthroughs are copied from the real files, and the output under each "Try it yourself" command was captured by running that command in this repository.

The repository is a small Azure web app that reads a secret from Key Vault and writes files to Blob Storage with a managed identity and no stored secret, and the Terraform that builds the Azure side of it.

Documentation formats (Markdown and Mermaid in the README and ARCHITECTURE files) have no note of their own: they hold prose and diagrams, and no code runs from them.

Every file follows the same nine headings: what it is, why this repository uses it, where it appears, how it works underneath, a walkthrough of this repository's own files, things to try, common mistakes, five questions with answers, and the official documentation.

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
