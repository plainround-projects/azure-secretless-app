# import-linter

*Fails the build when a layer imports something it must not. Pinned here: import-linter 2.15 (with grimp 3.18).*

## What it is

import-linter is a tool that checks which parts of a Python project are allowed to import which other parts. You write the rules in the configuration, and the tool builds a graph of every `import` in the code and fails if a rule is broken. It is how a layered design stays layered.

## Why this repository uses it

The layered design is a rule: domain depends on nothing, application on domain, and the Azure SDK appears only in the infrastructure layer. A written rule drifts; a failing check does not.

## Where it appears

| File | What it does with it |
|---|---|
| `pyproject.toml` | `[tool.importlinter]` and the three contracts. |
| `Makefile` | `make lint` runs `lint-imports`. |

## How it works underneath

The tool (using a library called grimp) reads the source files, finds every import statement and builds a directed graph: an arrow from the importing module to the imported one. A **contract** is a rule about that graph.

A `layers` contract lists packages from highest to lowest. A higher layer may import a lower one; a lower layer must never import a higher one. A `forbidden` contract says that one set of modules must not import another set, directly or (unless `allow_indirect_imports = true`) through a chain of other modules.

`lint-imports` reads `[tool.importlinter]` from `pyproject.toml`, runs each contract, and exits non-zero if any is broken.

## Walkthrough of this repository's use

```toml
[tool.importlinter]
root_package = "secretless_app"
include_external_packages = true

[[tool.importlinter.contracts]]
name = "Layers: interfaces -> infrastructure -> application -> domain, never upward"
type = "layers"
layers = [
    "secretless_app.interfaces",
    "secretless_app.infrastructure",
    "secretless_app.application",
    "secretless_app.domain",
]

[[tool.importlinter.contracts]]
name = "Domain and application know nothing about Azure or Flask"
type = "forbidden"
source_modules = ["secretless_app.domain", "secretless_app.application"]
forbidden_modules = ["azure", "flask", "werkzeug", "gunicorn"]

[[tool.importlinter.contracts]]
name = "Only the infrastructure layer imports the Azure SDK"
type = "forbidden"
source_modules = ["secretless_app.interfaces"]
forbidden_modules = ["azure"]
allow_indirect_imports = true
```

`root_package` is the package to analyze. `include_external_packages = true` puts third-party packages in the graph too, so contracts can forbid them.

The first contract is `type = "layers"`. The list is ordered from the top: `interfaces`, then `infrastructure`, `application`, `domain`. A higher layer may import a lower one; a lower one must never import a higher one. The second contract, `forbidden`, says the `domain` and `application` packages may not import `azure`, `flask`, `werkzeug` or `gunicorn`. The third forbids `interfaces` from importing `azure` directly. It carries `allow_indirect_imports = true` because the interfaces layer reaches the SDK through the infrastructure layer on purpose; without that line the contract failed when first written, which is the lesson to keep.

## Try it yourself

Check the three contracts.

```bash
.venv/bin/lint-imports
```

You should see something like this:

```text
╔══╗─────────▶╔╗ ╔╗      ╔╗◀───┐
╚╣╠╝◀─────┐  ╔╝╚╗║║────▶╔╝╚╗   │
 ║║   ╔══╦══╦╩╗╔╝║║  ╔╦═╩╗╔╝╔═╦══╗
 ║║╔══╣╔╗║╔╗║╔╣║ ║║ ╔╬╣╔╗║║ ║│║╔═╝
╔╣╠╣║║║╚╝║╚╝║║║╚╗║╚═╝║║║║║╚╗║═╣║
╚══╩╩╩╣╔═╩══╩╝╚═╝╚═══╩╩╝╚╩═╩╩═╩╝
  └──▶║║                    ▲
      ╚╝────────────────────┘


---------
Contracts
---------

...
Contracts: 3 kept, 0 broken.
```

Confirm the version.

```bash
.venv/bin/pip show import-linter | sed -n 1,2p
```

You should see something like this:

```text
Name: import-linter
Version: 2.15
```

## Mistakes people make

- Writing the layers in the wrong order. The first line is the top: nothing may import it.
- Forgetting that `forbidden` also forbids indirect imports unless you allow them; the first version of a contract here failed for exactly that reason.
- Adding an exception to make a violation pass instead of moving the code to the right layer.
- Not running it in CI. Here it is part of `make lint`.
- Expecting it to check third-party packages. It checks them only when `include_external_packages = true`.

## Check yourself

1. **What does a layers contract say?**
   Answer: Packages are listed top to bottom; a package may import those below it and never those above.

2. **What is an indirect import?**
   Answer: An import that reaches a module through a chain of other modules (A imports B, B imports C: A reaches C indirectly).

3. **Why is this check useful?**
   Answer: It makes the architecture a rule that fails the build, not a drawing that drifts.

4. **Where are the contracts written?**
   Answer: In `pyproject.toml` under `[tool.importlinter]`.

5. **What command runs the check?**
   Answer: `lint-imports`, which `make lint` calls.

## Further reading

- import-linter 2.15: https://import-linter.readthedocs.io/en/stable/
- Contract types: https://import-linter.readthedocs.io/en/stable/contract_types.html
