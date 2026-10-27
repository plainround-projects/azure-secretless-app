# 3. Ports and adapters, with an in-memory backend that ships

Status: accepted, 2026-10-27.

## Context

The app has two outbound dependencies (Key Vault, Blob Storage) that cannot be run locally with managed identity semantics. Tests must run without Azure, and a reader without a subscription should still be able to run the app and see a denial.

## Decision

Define `SecretStore` and `BlobStore` ports in the application layer. Provide Azure adapters and in-memory adapters in the infrastructure layer. `BACKEND=memory` selects the in-memory ones in the composition root, and `MEMORY_DENY=blob,vault` makes them raise the same named errors the Azure adapters translate to.

## Consequences

- The use cases have 100 percent test coverage without a mock library.
- The in-memory adapters are production code that only the demo and tests use. They are small, tested, and named for what they are; the alternative (fakes only in `tests/`) would leave `make run` unable to start without Azure.
- The Azure adapters are tested against an SDK stub and the error translation against constructed SDK exceptions; `make test-azure` runs the same calls against the real services.
