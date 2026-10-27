# 1. A separate identity pulls the image

Status: accepted, 2026-10-27.

## Context

The lesson's Done when for step 3 asks that the app identity's role assignments list exactly two entries. A container app that pulls from a private registry also needs a pull permission (AcrPull) for some identity.

## Decision

Create a second user-assigned identity, `id-secretless-pull`, that holds `AcrPull` on the registry and is named in the app's `registry` block. The application code never uses it. The app identity keeps the two data roles.

## Consequences

- The "exactly two" check stays true and is asserted by `terraform test`.
- One more free resource and one more role assignment to explain.
- The admin user of the registry stays disabled, so there is no shared registry password either.
- Alternative rejected: attaching `AcrPull` to the app identity. It works, but the app could then pull any image in the registry, which the code never needs.
