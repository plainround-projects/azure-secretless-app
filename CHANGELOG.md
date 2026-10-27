# Changelog

All notable changes to this project are recorded here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses [Semantic Versioning](https://semver.org/).

## [0.1.0] - 2026-10-27

### Added

- `tech/`: 34 technology notes (language, libraries, tools, services, file formats) with an index, a reading order and a ten-minute shortlist; every code quote is copied from the repository and every command's output was captured by running it.
- A layered Flask app (`domain`, `application`, `infrastructure`, `interfaces`) with `/live`, `/health` and `/upload/<name>`, Azure adapters that authenticate only with `DefaultAzureCredential`, in-memory adapters for offline runs, JSON logging and graceful shutdown.
- Terraform modules (`log_analytics`, `user_assigned_identity`, `key_vault`, `storage_uploads`, `role_assignments`, `container_registry`, `container_app`, `budget`) and the `dev` environment, each module with a README and `terraform test` tests against a mocked provider.
- The lesson's runbook as scripts (`provision`, `seed-secret`, `prove-key-access-closed`, `build-and-deploy`, `smoke`, `audit-config`, `break-and-measure`, `read-denials`, `teardown`).
- A multi-stage Dockerfile that runs as a non-root user, hash-pinned lock files, import-linter, ruff, mypy, tflint and checkov configuration, and a CI workflow.
- `docs/RUNBOOK.md`: the signals, causes and fixes for each failure, and the table for the measured propagation times.
