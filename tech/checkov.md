# Checkov

*Scans the Terraform, Dockerfile and workflow for security misconfigurations. Pinned here: Checkov 3.3.30.*

## What it is

Checkov is a security scanner for infrastructure files. It reads Terraform (and Dockerfiles and GitHub workflows) and compares each resource with hundreds of rules such as "storage accounts must not allow public blobs". It reports each rule as passed, failed or skipped.

## Why this repository uses it

The template asks for `checkov` in CI. Most findings were fixed in the modules; 19 deliberate exceptions are skipped with a reason beside the code.

## Where it appears

| File | What it does with it |
|---|---|
| `.checkov.yaml` | What to scan. |
| `infra/modules/*/main.tf` | Inline `#checkov:skip` comments with reasons. |
| `Makefile` | `make scan`. |
| `.github/workflows/ci.yml` | The `checkov` job. |

## How it works underneath

Checkov parses the Terraform into a graph, evaluates variables where it can, and runs each **check** (each named like `CKV_AZURE_59`) against the matching resources. A failed check prints the resource, file and a guide link.

You can **skip** a check with a comment inside the resource: `#checkov:skip=CKV_AZURE_59:reason`. The reason after the second colon is shown in the report. This repository puts every skip with its reason beside the resource it affects, so a reviewer reads the trade-off next to the code. `.checkov.yaml` selects folders, frameworks, and a `var-file` so variables are evaluated as in the final deployment.

## Walkthrough of this repository's use

```yaml
directory:
  - infra
  - .github
file:
  - Dockerfile
framework:
  - terraform
  - dockerfile
  - github_actions
download-external-modules: false
evaluate-variables: true
```

Scans `infra/` and `.github/`, plus the Dockerfile, for three frameworks. `evaluate-variables` lets checkov substitute variable values.

```hcl
resource "azurerm_container_registry" "this" {
  #checkov:skip=CKV_AZURE_163:vulnerability scanning needs Microsoft Defender for Containers
  #checkov:skip=CKV_AZURE_164:signed images need the Premium SKU
  #checkov:skip=CKV_AZURE_165:geo-replication needs the Premium SKU
  #checkov:skip=CKV_AZURE_166:image quarantine needs the Premium SKU
  #checkov:skip=CKV_AZURE_167:the untagged-manifest retention policy needs the Premium SKU
  #checkov:skip=CKV_AZURE_233:zone redundancy needs the Premium SKU
  #checkov:skip=CKV_AZURE_237:dedicated data endpoints need the Premium SKU
  #checkov:skip=CKV_AZURE_139:disabling public access needs the Premium SKU and a private endpoint; the pull is authorized by an identity with AcrPull
  name                = var.name
  resource_group_name = var.resource_group_name
  location            = var.location
  sku                 = var.sku
  tags                = var.tags

  # No shared admin username and password: images are pulled by an identity holding AcrPull on this registry.
  admin_enabled          = false
  anonymous_pull_enabled = false
}
```

Each skip is a comment inside the resource: `#checkov:skip=CHECK_ID:reason`. These registry checks need the Premium tier, which this practice project does not use. The reasons are read where the code is, not in a separate list.

```hcl
  #checkov:skip=CKV_AZURE_189:public endpoint stays on so the operator can seed the secret; the private endpoint is the azure-private-platform-slice project
  #checkov:skip=CKV_AZURE_109:no firewall rules for the same reason
  #checkov:skip=CKV2_AZURE_32:a private endpoint for the vault is the lesson's stretch goal
  #checkov:skip=CKV_AZURE_110:purge protection is the purge_protection_enabled variable, off for practice so a vault can be purged; on in production
  #checkov:skip=CKV_AZURE_42:recoverable means soft delete (always on, 7 to 90 days) plus purge protection, which is the variable above
```

For the vault: public access stays on so the operator can seed the secret; purge protection is a variable that is off for practice. The next project in this track turns public access off.

### Every line, in order

This part walks through every file this note is responsible for, from the first non-blank line to the last, in blocks. Each block shows the lines (the numbers say where they sit in the file) and then explains them. New ideas are explained at the first place they are needed; later blocks use them without repeating the explanation.

#### `.checkov.yaml`

14 lines of code and comments. Each block below quotes consecutive lines of the file, with the line numbers, and explains them.

**Lines 1 to 3**

```yaml
# checkov over the Terraform in infra/, the Dockerfile and the workflow. Findings that are deliberate choices for this
# teaching slice carry an inline `checkov:skip=ID:reason` next to the resource, so each skip and its reason can be
# read where the code is; nothing is skipped here.
```

**New idea.** **Azure Blob Storage** stores files (*blobs*) in a *storage account*. Blobs live in *containers*, which work like top-level folders, and each blob is addressed by account, container and name. (This "container" is not a Docker container.)

**New idea.** A **container** is a packaged program together with everything it needs, run in isolation from the rest of the machine. An **image** is the read-only package a container starts from, built with a *Dockerfile*. A **registry** stores images so that other machines can pull them.

A comment of three lines. **checkov** is a scanner that reads infrastructure code (and Dockerfiles and workflow files) and reports settings that are risky, such as a storage account open to the public. Where a finding is a deliberate choice, the code carries an inline `checkov:skip=RULE:reason` comment next to the resource, so each exception and its reason can be read where it applies. This configuration file itself skips nothing.

**Lines 4 to 6**

```yaml
directory:
  - infra
  - .github
```

`directory:` followed by an indented list. **YAML** is a data format built on indentation: a line ending in `:` names a key, and lines starting with `- ` below it, indented, are the items of a list. This list tells checkov to scan every file under `infra` (all Terraform) and under `.github` (the CI workflow).

**Lines 7 to 8**

```yaml
file:
  - Dockerfile
```

`file:` lists single files to scan: here the `Dockerfile` in the repository root.

**Lines 9 to 12**

```yaml
framework:
  - terraform
  - dockerfile
  - github_actions
```

`framework:` lists the kinds of files to check: `terraform`, `dockerfile` and `github_actions`. Limiting the list keeps checkov from trying rule sets that do not apply.

**Line 13**

```yaml
download-external-modules: false
```

`download-external-modules: false` stops checkov from downloading modules from the internet while scanning. It checks only the modules that are in this repository, so the result does not depend on the network.

**Line 14**

```yaml
evaluate-variables: true
```

`evaluate-variables: true` makes checkov work out the values of Terraform variables (from their defaults) before applying rules, so a rule such as "public access must be off" sees `false` instead of the text `var.public_network_access_enabled`.

## Try it yourself

Run the scan and read the totals.

```bash
make scan CHECKOV="uvx --from checkov==3.3.30 checkov" 2>&1 | grep -E 'Passed|results'
```

You should see something like this:

```text
terraform scan results:
Passed checks: 14, Failed checks: 0, Skipped checks: 19
terraform scan results:
Passed checks: 28, Failed checks: 0, Skipped checks: 38
github_actions scan results:
Passed checks: 63, Failed checks: 0, Skipped checks: 0
```

Count the skips per module.

```bash
grep -rc 'checkov:skip' infra/modules | grep -v ':0'
```

You should see something like this:

```text
infra/modules/container_registry/main.tf:8
infra/modules/key_vault/main.tf:5
infra/modules/storage_uploads/main.tf:6
```

## Mistakes people make

- Skipping a check without a reason. Each skip here says why.
- Treating the score as proof of security. It finds known misconfigurations only.
- Skipping instead of fixing when the fix is a one-line change.
- Scanning with default variable values that differ from the real ones; that is what `var-file` fixes.
- Ignoring skips when the lesson moves on (for example once a private endpoint exists).

## Check yourself

1. **What does a check ID like `CKV_AZURE_59` identify?**
   Answer: One rule about one kind of misconfiguration.

2. **How do you skip a check?**
   Answer: With a `#checkov:skip=ID:reason` comment inside the resource.

3. **Why put the reason in the comment?**
   Answer: So the next reader sees the trade-off beside the code.

4. **What does `evaluate-variables` do?**
   Answer: Lets checkov substitute variable values before checking.

5. **Does a passing scan mean the system is secure?**
   Answer: No; it only means known misconfigurations were not found.

## Further reading

- Checkov 3.3: https://www.checkov.io/
- Suppressing checks: https://www.checkov.io/2.Basics/Suppressing%20and%20Skipping%20Policies.html
