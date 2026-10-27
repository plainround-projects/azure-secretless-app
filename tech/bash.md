# Bash

*The scripts under `scripts/` that run the lesson against Azure. Pinned here: Bash 3.2 and newer (macOS ships 3.2).*

## What it is

Bash is a **shell**: a program that reads commands you type (or that are written in a file) and runs them. A file of commands is a **shell script**. Scripts are the glue between tools: they call `terraform`, `az` and `curl` in the right order and stop if one fails.

## Why this repository uses it

The lesson's steps are commands you type in order. The scripts are those commands, written down once, with the retries and checks a person forgets, so you run `make up` instead of copying thirty lines.

## Where it appears

| File | What it does with it |
|---|---|
| `scripts/lib.sh` | Shared helpers: `log`, `die`, `need`, `require_login`, `tf_out`, `retry`. |
| `scripts/provision.sh` | Registers providers, writes variables, applies Terraform, seeds the secret. |
| `scripts/seed-secret.sh` | Sets the partner key in the vault, retrying while the role spreads. |
| `scripts/prove-key-access-closed.sh` | Proves account keys are refused. |
| `scripts/build-and-deploy.sh` | Builds the image and adds the app. |
| `scripts/smoke.sh` | Checks the roles, the health route and an upload. |
| `scripts/audit-config.sh` | Searches the deployed configuration and the source for credentials. |
| `scripts/break-and-measure.sh` | Removes a role and times the effect. |
| `scripts/read-denials.sh` | Queries the logs for the denial. |
| `scripts/teardown.sh` | Destroys everything. |
| `scripts/docker-smoke.sh` | Runs the image and calls it. |

## How it works underneath

A command line is split into words. The first word is the program, the rest are **arguments**. The shell starts the program as a new process and waits. When the process ends it leaves an **exit code**: `0` means success, anything else means failure. `&&` runs the next command only if the last one succeeded; `||` only if it failed; `|` (a **pipe**) sends the output of one command to the input of the next.

A **variable** is set with `NAME=value` and read with `$NAME`. Always put it in double quotes (`"$NAME"`) so spaces in the value do not split it into several words. `$(command)` runs a command and substitutes its output. `source file` runs another script's lines in the current shell, so its functions and variables become available.

`set -euo pipefail` makes a script strict: `-e` stops at the first failing command, `-u` treats an unset variable as an error, `-o pipefail` makes a pipe fail if any command in it fails. `trap 'command' EXIT` runs a command when the script ends, even after an error, which is how temporary files get cleaned up.

macOS ships Bash 3.2. Scripts here avoid newer features (such as negative array indexes and `${var^^}`) so they run there.

## Walkthrough of this repository's use

### The shared helpers

```bash
#!/usr/bin/env bash
# Shared helpers for the runbook scripts. Source it; do not run it.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TF_DIR="$ROOT/infra/environments/dev"
APP_VERSION="$(sed -n 's/^version = "\(.*\)"/\1/p' "$ROOT/pyproject.toml" | head -1)"
export APP_VERSION
```

`#!/usr/bin/env bash` (the **shebang**) tells the system which program runs the file. `set -euo pipefail` makes the script strict (see the explanation above). `ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"` finds the repository root: `${BASH_SOURCE[0]}` is this file's path, `dirname` removes the file name, `cd ... && pwd` turns it into an absolute path. `sed -n 's/^version = "\(.*\)"/\1/p'` prints the project version from `pyproject.toml`: `-n` prints only lines that match, `s/old/new/p` substitutes and prints, and `\(.*\)` captures the version text. `export` hands the variable to programs the script starts.

```bash
log() { printf '%s %s\n' "$(date -u +%H:%M:%S)" "$*"; }
die() { printf 'error: %s\n' "$*" >&2; exit 1; }
```

`log` prints the time (UTC) and its arguments (`$*`). `die` prints to standard error (`>&2`) and stops with exit code 1. Both are one-line **functions**.

```bash
need() {
  for tool in "$@"; do
    command -v "$tool" >/dev/null || die "$tool is not installed"
  done
}
```

`need` takes any number of tool names (`"$@"` is all the arguments, each quoted). `command -v tool` succeeds if the tool exists; `>/dev/null` throws its output away; `|| die ...` runs only on failure.

```bash
require_login() {
  need az
  az account show >/dev/null 2>&1 || die "not signed in: run 'az login' first"
}
```

`az account show` succeeds only when you are signed in. `2>&1` merges errors into the output so both are discarded.

```bash
tf_out() { terraform -chdir="$TF_DIR" output -raw "$1"; }
```

`terraform -chdir=DIR output -raw NAME` prints one Terraform output with no quotes, so a script can use `$(tf_out key_vault_name)`.

```bash
retry() {
  local attempts=$1 pause=$2 attempt=1
  shift 2
  until "$@"; do
    if ((attempt >= attempts)); then return 1; fi
    log "attempt $attempt of $attempts failed; waiting ${pause}s for the role assignment to take effect"
    sleep "$pause"
    attempt=$((attempt + 1))
  done
}
```

`retry 12 30 command...` runs the command up to 12 times, waiting 30 seconds after each failure. `local` makes variables private to the function. `shift 2` drops the first two arguments so `"$@"` is the command. `until "$@"; do ... done` repeats until the command succeeds. `((attempt >= attempts))` is arithmetic. This exists because a role takes minutes to spread and the first data-plane calls fail with 403 until then.

### provision.sh

```bash
AUTO_APPROVE=""
[[ "${1:-}" == "--yes" ]] && AUTO_APPROVE="-auto-approve"
```

The first argument `--yes` becomes `-auto-approve` for Terraform. `${1:-}` is "the first argument, or nothing if there is none" (needed because `set -u` forbids unset variables).

```bash
for provider in Microsoft.App Microsoft.ContainerRegistry Microsoft.Consumption Microsoft.Insights \
  Microsoft.KeyVault Microsoft.ManagedIdentity Microsoft.OperationalInsights Microsoft.Storage; do
  log "registering $provider"
  az provider register --namespace "$provider" --wait >/dev/null
done
```

A `for` loop over the Azure resource providers this project needs. `az provider register --namespace "$provider" --wait` registers each in the subscription and waits. The line continues with a backslash at the end of the line.

```bash
TFVARS="$TF_DIR/terraform.tfvars"
if [[ ! -f "$TFVARS" ]]; then
  [[ -n "${BUDGET_EMAIL:-}" ]] || die "set BUDGET_EMAIL=you@example.com (lesson step 1: a budget alert), or write $TFVARS yourself"
  log "writing $TFVARS from your az session (it holds ids, so it is git-ignored)"
  cat >"$TFVARS" <<TFVARS_EOF
subscription_id       = "$(az account show --query id --output tsv)"
tenant_id             = "$(az account show --query tenantId --output tsv)"
deployer_object_id    = "$(az ad signed-in-user show --query id --output tsv)"
budget_contact_emails = ["$BUDGET_EMAIL"]
budget_start_date     = "$(date -u +%Y-%m-01T00:00:00Z)"
TFVARS_EOF
fi
```

If the variables file does not exist, the script writes it from your `az` session. `<<TFVARS_EOF ... TFVARS_EOF` is a **here-document**: everything up to the marker is the file's content, with `$(...)` expanded. The budget address must come from `BUDGET_EMAIL`, and `${BUDGET_EMAIL:-}` with `-n` tests "not empty". `date -u +%Y-%m-01T00:00:00Z` gives the first of the current month, which Azure requires.

### seed-secret.sh and the retry

```bash
VALUE="${PARTNER_API_KEY:-demo-value-123}"

# The deployer's Secrets Officer role was assigned seconds ago; Owner alone cannot write secrets, and the role can take
# a few minutes to apply, so retry on 403.
retry 12 30 az keyvault secret set --vault-name "$VAULT" --name partner-api-key --value "$VALUE" --output none
log "secret partner-api-key set in $VAULT (length ${#VALUE})"
```

`${PARTNER_API_KEY:-demo-value-123}` uses the environment variable or the lesson's demo value. The call is wrapped in `retry 12 30`. `${#VALUE}` is the length of the text, so the log shows a length and never the value.

### prove-key-access-closed.sh

```bash
if output="$(az storage container list --account-name "$ACCOUNT" --auth-mode key 2>&1)"; then
  die "listing containers with an account key SUCCEEDED: shared key access is not disabled"
fi
grep -q "KeyBasedAuthenticationNotPermitted" <<<"$output" || die "the key request failed, but not with KeyBasedAuthenticationNotPermitted: $output"
log "OK: --auth-mode key is refused with KeyBasedAuthenticationNotPermitted"
```

`if output="$(command 2>&1)"; then ... fi` runs a command and tests whether it succeeded. Here success is the failure: if listing containers with an account key works, shared keys are not disabled and the script stops. `grep -q ... <<<"$output"` checks the text for `KeyBasedAuthenticationNotPermitted` (`-q` prints nothing, `<<<` feeds a string to the command).

### break-and-measure.sh

```bash
case "$TARGET" in
  blob)
    ROLE="Storage Blob Data Contributor"
    SCOPE="$(az storage account show --name "$ACCOUNT" --resource-group "$RG" --query id --output tsv)/blobServices/default/containers/$(tf_out container_name)"
    probe() { curl --silent --output /dev/null --write-out '%{http_code}' -X POST --data-binary "probe" "$URL/upload/probe.txt"; }
    expect_ok=201
    ;;
  vault)
    ROLE="Key Vault Secrets User"
    SCOPE="$(az keyvault show --name "$VAULT" --query id --output tsv)"
    probe() { curl --silent --output /dev/null --write-out '%{http_code}' "$URL/health"; }
    expect_ok=200
    ;;
  *) die "usage: $0 blob|vault" ;;
esac
```

`case ... esac` picks a branch by the first argument. Each branch defines the role, its scope and a `probe` function that returns an HTTP status. The other branch of the `case` (`*)`) prints the usage and stops.

```bash
wait_for() { # wait_for <description> <predicate: "refused" or "ok">
  local start end status
  start=$(date +%s)
  while true; do
    status="$(probe || true)"
    if [[ "$2" == "refused" && "$status" == "502" ]] || [[ "$2" == "ok" && "$status" == "$expect_ok" ]]; then break; fi
    sleep 10
  done
  end=$(date +%s)
  log "$1: $((end - start)) seconds (last status $status)"
}
```

`date +%s` is the Unix time in seconds, so subtracting two readings gives elapsed seconds. The loop sends the probe every 10 seconds until the status is what is expected.

### teardown.sh

```bash
PROTECTED="$(az keyvault list-deleted --query "[?name=='$VAULT'].properties.purgeProtectionEnabled | [0]" --output tsv)"
if [[ "$PROTECTED" == "true" ]]; then
  log "purge protection is on: the name stays reserved until the date above and cannot be purged"
elif [[ -n "$PROTECTED" ]]; then
  log "purge protection is off: purging frees the name now"
  if [[ -n "$AUTO_APPROVE" ]]; then
    az keyvault purge --name "$VAULT"
  else
    log "run: az keyvault purge --name $VAULT"
  fi
```

Reads whether the deleted vault has purge protection, using a JMESPath query with `--output tsv`, then prints what that means.

### docker-smoke.sh

```bash
IMAGE="${1:?usage: docker-smoke.sh <image>}"
NAME="secretless-smoke-$$"
trap 'docker rm -f "$NAME" >/dev/null 2>&1 || true' EXIT
```

`${1:?usage: ...}` stops with that message if no argument was given. `trap 'docker rm -f "$NAME" ...' EXIT` removes the test container however the script ends. `$$` is the script's own process id, used to make a unique container name.

### Every line, in order

This part walks through every file this note is responsible for, from the first non-blank line to the last, in blocks. Each block shows the lines (the numbers say where they sit in the file) and then explains them. New ideas are explained at the first place they are needed; later blocks use them without repeating the explanation.

#### `scripts/audit-config.sh`

23 lines of code and comments. Each block below quotes consecutive lines of the file, with the line numbers, and explains them.

**Line 1**

```bash
#!/usr/bin/env bash
```

**New idea.** An **environment variable** is a named text value that the operating system hands to every program it starts, such as `PORT=8080`. It is the usual way to configure a program without changing its code, and the way a deployment passes settings that differ between machines.

**New idea.** A **terminal** is a window in which you type commands and read the answers. The program that reads what you type is the **shell**; this project uses **bash**, the most common one. A command is a program name followed by arguments separated by spaces, such as `ls -l docs`; options usually start with `-` or `--`.

**New idea.** A **shell script** is a text file of commands that bash runs from top to bottom, as if you had typed them one after another. Putting them in a file makes a routine repeatable and reviewable.

**New idea.** The first line `#!/usr/bin/env bash` is called a **shebang**. When the file is run directly, the operating system reads this line to learn which program should interpret the file: `env bash` finds `bash` wherever it is installed on this machine.



**Lines 2 to 3**

```bash
# Step 4 "Done when": a search of the app's configuration and source finds no key, password or connection string.
# It looks for credential *values* (the word "key" appears in the secret's name, which is harmless).
```

**New idea.** In a shell script a `#` starts a **comment**: everything to the end of the line is ignored by bash and is there for the reader.

A comment block: this is the lesson's step 4 check that a search of the app's configuration and source finds no key, password or connection string. It looks for credential *values*, not the word "key" (which appears harmlessly in the secret's name).

**Lines 4 to 5**

```bash
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
```

**New idea.** A **retry** repeats an operation that failed, usually after a pause. It helps with failures that go away by themselves, such as a new permission that takes a few minutes to spread; it must be limited, so a permanent failure is reported and not repeated forever.

**New idea.** `set` changes how bash behaves for the rest of the script. `-e` stops the script at the first command that fails (a command *fails* when it ends with a non-zero **exit status**; zero means success). `-u` makes using a variable that was never set an error instead of silently giving an empty text. `-o pipefail` makes a pipeline (commands joined with `|`) fail if *any* of its commands fails, not only the last. Together they turn silent mistakes into immediate, visible stops.

**New idea.** Every command ends with a number, its **exit status**: `0` means it worked and anything else means it failed. `$?` holds the status of the last command. `&&` runs the next command only if the previous one succeeded, `||` only if it failed.

**New idea.** `source file` (or `. file`) runs the commands of another script *inside the current script*, so the functions and variables it defines become available here. It is used for shared helper code; a script that is run normally would start a separate process and its definitions would be lost.

**New idea.** `${BASH_SOURCE[0]}` is the path of the script file being run (or sourced) right now. `dirname` cuts off the file name and leaves the folder, so `$(dirname "${BASH_SOURCE[0]}")` is the folder the script lives in, and the script finds its neighbors no matter where it is started from.

`source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"` loads the shared helpers (`log`, `die`, `need`, `require_login`, `tf_out`, `retry`, and the variables `ROOT` and `TF_DIR`) from `lib.sh`, which sits in the same folder as this script.

**Lines 6 to 7**

```bash
need az terraform grep
require_login
```

`need az terraform grep` requires the three programs; `require_login` requires an Azure sign-in.

**Line 9**

```bash
PATTERN='AccountKey=|SharedAccessSignature=|[?&]sig=|DefaultEndpointsProtocol=|password=|pwd=|client_secret|-----BEGIN [A-Z ]*PRIVATE KEY'
```

**New idea.** A **regular expression** is a compact pattern for matching text: `[a-z]` is one lowercase letter, `+` means one or more, `^` and `$` mark the start and end, `{1,127}` means one to 127 repeats.

**New idea.** Double quotes keep the text between them as one argument and still expand variables; single quotes keep it exactly as written, with no expansion at all.

`PATTERN` holds a search pattern in single quotes (so nothing is expanded). It is an **extended regular expression**, a compact description of text shapes, and `|` means "or". The shapes: `AccountKey=` and `DefaultEndpointsProtocol=` (parts of a storage connection string), `SharedAccessSignature=` and `[?&]sig=` (a signed access link; `[?&]` is either character), `password=`, `pwd=`, `client_secret`, and `-----BEGIN [A-Z ]*PRIVATE KEY` (the first line of a private key file; `[A-Z ]*` is any run of capital letters and spaces).

**Lines 11 to 13**

```bash
APP="$(tf_out app_name)"
RG="$(tf_out resource_group_name)"
CONFIG="$(az containerapp show --resource-group "$RG" --name "$APP" --output json)"
```

**New idea.** **JSON** is a text format for data: objects `{"name": value}`, lists `[1, 2]`, strings, numbers, `true`, `false` and `null`. Most web services send and receive their data as JSON because every programming language can read it.

**New idea.** An Azure **resource group** is a folder-like container for the resources of one project. Resources in a group share a life cycle: deleting the group deletes everything in it.

**New idea.** A **Terraform output** is a named value the code publishes after `apply`, such as a resource name. The scripts read them with `terraform output -raw NAME` instead of repeating names by hand.

**New idea.** **`az`** is the Azure command-line program. `az <group> <command> --option value` calls the Azure management service; `--output tsv` prints plain values, `--output table` prints a table, and `--query '<expression>'` picks parts of the JSON answer using a query language called JMESPath.

`APP` and `RG` are the app name and the resource group from Terraform outputs. `CONFIG` captures the deployed app's complete configuration: `az containerapp show --resource-group ... --name ... --output json` prints it as JSON text, and `$(...)` stores that text in the variable.

**Lines 15 to 16**

```bash
log "environment variables of the deployed container (names and values)"
jq -r '.properties.template.containers[].env[] | "\(.name)=\(.value // "<secretRef " + (.secretRef // "") + ">")"' <<<"$CONFIG"
```

**New idea.** `jq` is a command-line tool for reading JSON: `jq -r '.name'` prints the field `name` of the JSON it reads, without quotes (`-r`, raw).

**New idea.** **Redirection** changes where a command reads from or writes to: `> file` writes its output into a file (replacing it), `>> file` appends, `< file` reads input from a file, `2>&1` sends the error stream to the same place as the normal output, and `>/dev/null` throws the output away (`/dev/null` is a special file that discards everything written to it).

`log` announces the step. Then `jq -r '...' <<<"$CONFIG"` reads the stored JSON (`<<<` hands the variable's text to the command as input). The filter walks `.properties.template.containers[].env[]`: for every container and each of its environment variables it builds a line `name=value`. The `//` operator means "or, if that is empty": when a variable has no `value`, the line shows `<secretRef name>`, which would mean the value came from an app secret. In this project no such line should appear.

**Lines 18 to 20**

```bash
log "secrets defined on the app (must be empty)"
SECRETS="$(jq -r '.properties.configuration.secrets // [] | length' <<<"$CONFIG")"
[[ "$SECRETS" == "0" ]] || die "the app defines $SECRETS secret(s)"
```

**New idea.** `[[ condition ]]` tests a condition and succeeds or fails like a command. Common tests: `-f path` (a regular file exists), `-n text` (the text is not empty), `-z text` (the text is empty), `a == b` and `a != b` (text equality). `!` negates a test.

Logs the step, then `jq -r '.properties.configuration.secrets // [] | length'` counts the secrets defined on the app (an absent list counts as empty). The check `[[ "$SECRETS" == "0" ]] || die ...` stops the script unless the count is exactly zero: the design is that the app defines no secrets at all.

**Lines 22 to 23**

```bash
if grep -Eq "$PATTERN" <<<"$CONFIG"; then die "the deployed configuration contains a credential-shaped value"; fi
log "OK: no credential-shaped value in the deployed configuration"
```

**New idea.** `grep pattern` prints the lines that contain the pattern; `-q` prints nothing and only sets the exit status; `-c` prints how many lines matched; `-E` allows extended regular expressions.

**New idea.** `if command; then ... elif ...; else ...; fi` runs the first block whose condition command succeeds. The word `fi` (`if` reversed) ends it.

`grep -Eq "$PATTERN" <<<"$CONFIG"` is true if the configuration text contains anything that looks like a credential; then the script stops with `die`. Otherwise `log` reports success.

**Lines 25 to 29**

```bash
if grep -rEn "$PATTERN" "$ROOT/src" "$ROOT/requirements.lock" "$ROOT/Dockerfile" >/dev/null; then
  grep -rEn "$PATTERN" "$ROOT/src" "$ROOT/requirements.lock" "$ROOT/Dockerfile"
  die "the source contains a credential-shaped value"
fi
log "OK: no credential-shaped value in the source, the lock file or the Dockerfile"
```

**New idea.** A **container** is a packaged program together with everything it needs, run in isolation from the rest of the machine. An **image** is the read-only package a container starts from, built with a *Dockerfile*. A **registry** stores images so that other machines can pull them.

**New idea.** A **lock file** records the exact versions (and often the hashes) of every package a project uses, including packages that those packages need. Installing from it gives the same result on every machine and on every day.

The same search over the files the app is built from. `grep -rEn "$PATTERN" src requirements.lock Dockerfile` searches recursively (`-r`) with an extended pattern (`-E`) and line numbers (`-n`). The first call runs silently (`>/dev/null`) only to see whether there is a match; if there is, the second call prints the matching lines and `die` stops the script. Otherwise the last line logs success.

#### `scripts/break-and-measure.sh`

50 lines of code and comments. Each block below quotes consecutive lines of the file, with the line numbers, and explains them.

**Line 1**

```bash
#!/usr/bin/env bash
```



**Lines 2 to 4**

```bash
# Step 5: remove one role, time how long until the app is refused, restore it, time how long until it recovers.
#   scripts/break-and-measure.sh blob     removes Storage Blob Data Contributor (watch POST /upload)
#   scripts/break-and-measure.sh vault    removes Key Vault Secrets User (watch GET /health)
```

**New idea.** **Azure role-based access control (RBAC)** decides who may do what. A *role* is a named bundle of permissions (for example "Key Vault Secrets User" may read secrets), a *scope* is where the grant applies (one resource, a resource group, a whole subscription), and a *role assignment* connects an identity, a role and a scope. The smaller the scope, the less a leaked identity can do.

**New idea.** **Azure Key Vault** stores secrets, keys and certificates behind Azure's access control and writes an audit record of every use. A program reads a secret by calling the vault with its identity, so the secret never has to sit in a file or in the program's settings.

**New idea.** **Azure Blob Storage** stores files (*blobs*) in a *storage account*. Blobs live in *containers*, which work like top-level folders, and each blob is addressed by account, container and name. (This "container" is not a Docker container.)

**New idea.** A **health check** is a small request that a platform sends to a running program to ask whether it is working. A *liveness* check that keeps failing makes the platform restart the program; a *readiness* check that fails keeps traffic away from it.

A comment block: lesson step 5. The script removes one role, times how long it takes until the app is refused, restores the role and times how long it takes until the app works again. The two usages: `blob` removes `Storage Blob Data Contributor` (watch `POST /upload`), `vault` removes `Key Vault Secrets User` (watch `GET /health`).

**Lines 5 to 6**

```bash
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
```

`source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"` loads the shared helpers (`log`, `die`, `need`, `require_login`, `tf_out`, `retry`, and the variables `ROOT` and `TF_DIR`) from `lib.sh`, which sits in the same folder as this script.

**Lines 7 to 8**

```bash
need az terraform curl
require_login
```

**New idea.** **HTTP** is the protocol of the web. A client sends a *request* (a method such as GET or POST, a path, headers and sometimes a body) and the server sends back a *response* with a three-digit **status code**: 200 means success, 201 created, 400 the request was bad, 403 forbidden, 404 not found, 413 too large, 502 a server behind this one failed.

`need az terraform curl` requires the three programs (`curl` is the command-line program that sends web requests); `require_login` requires an Azure sign-in.

**Lines 10 to 15**

```bash
TARGET="${1:-}"
URL="$(tf_out app_url)"
PRINCIPAL="$(tf_out app_identity_principal_id)"
ACCOUNT="$(tf_out storage_account_name)"
VAULT="$(tf_out key_vault_name)"
RG="$(tf_out resource_group_name)"
```

**New idea.** A **URL** is the full address of something on the web, such as `https://example.com:8443/path?x=1`: the protocol, the host name, an optional port, the path and an optional query.

**New idea.** **Microsoft Entra ID** (formerly Azure Active Directory) is the identity service of Azure. A **tenant** is one organization's directory in it. Every identity in the directory (a person, a group, an application, a managed identity) has an *object id*, and the party that receives permissions is called the *principal*.

**New idea.** A **managed identity** is an identity that Azure creates and looks after for a workload, with no password to store or rotate. When the workload runs, it asks a local Azure endpoint for a token for that identity. A *user-assigned* identity exists on its own and can be attached to several resources; its *client id* names it when a program asks for a token and its *principal id* names it when roles are granted.

**New idea.** `${NAME:-default}` is the value of the variable, or `default` if it is unset or empty. `${NAME:?message}` stops the script with the message if it is unset or empty. `${1:-}` reads the first argument or an empty text, which also avoids an error under `set -u`.

`TARGET` is the first argument (`blob` or `vault`), or empty. The other variables are values read from Terraform outputs: the app's address, the object id of the app's identity (`PRINCIPAL`), the storage account, the key vault and the resource group.

**Lines 17 to 23**

```bash
case "$TARGET" in
  blob)
    ROLE="Storage Blob Data Contributor"
    SCOPE="$(az storage account show --name "$ACCOUNT" --resource-group "$RG" --query id --output tsv)/blobServices/default/containers/$(tf_out container_name)"
    probe() { curl --silent --output /dev/null --write-out '%{http_code}' -X POST --data-binary "probe" "$URL/upload/probe.txt"; }
    expect_ok=201
    ;;
```

**New idea.** `case value in pattern) ...;; esac` picks the first block whose pattern matches the value; `*)` matches anything else.

**New idea.** `name() { ... }` defines a **function**: a named group of commands that is run by writing its name like a command. Inside, `$1`, `$2`, ... are the arguments it was called with, `"$@"` is all of them as separate words, and `"$*"` is all of them joined into one text. `return N` leaves the function with status N.

**New idea.** `curl` sends an HTTP request and prints the answer: `-s` silences the progress meter, `-S` still shows errors, `-f` makes a server error (status 400 or more) a failure, and `-w` prints extra information such as the status code after the body.

`case "$TARGET" in` chooses the block whose pattern equals the argument. The `blob` branch sets `ROLE` to the role being removed and `SCOPE` to the one container it applies to: `az storage account show ... --query id --output tsv` gives the storage account's id, to which the path `/blobServices/default/containers/<name>` is added. It then defines the function `probe`, which sends one request and prints only the HTTP status code: `curl --silent --output /dev/null --write-out '%{http_code}'` hides the body and the progress meter and writes the numeric status; `-X POST --data-binary "probe" "$URL/upload/probe.txt"` sends a POST request with the body `probe` to the upload route. `expect_ok=201` is the status that means success for an upload (201, "created"). The `;;` ends the branch.

**Lines 24 to 29**

```bash
  vault)
    ROLE="Key Vault Secrets User"
    SCOPE="$(az keyvault show --name "$VAULT" --query id --output tsv)"
    probe() { curl --silent --output /dev/null --write-out '%{http_code}' "$URL/health"; }
    expect_ok=200
    ;;
```

The `vault` branch is the same idea for the key vault: the role is `Key Vault Secrets User`, the scope is the vault's id (`az keyvault show ... --query id`), `probe` requests `GET /health` (which reads the secret) and success is status 200.

**Lines 30 to 31**

```bash
  *) die "usage: $0 blob|vault" ;;
esac
```

`*) die "usage: $0 blob|vault" ;;` is the branch for anything else: it stops with a usage message (`$0` is the name the script was started with). `esac` (`case` reversed) ends the `case`.

**Line 33**

```bash
[[ "$(probe)" == "$expect_ok" ]] || die "the app does not work before the break; run scripts/smoke.sh first"
```

A safety check before breaking anything: the probe must already return the success status. `$(probe)` runs the function and captures the status code it prints. If the app does not work yet, the script stops and points to `smoke.sh`.

**Lines 35 to 45**

```bash
wait_for() { # wait_for <description> <predicate: "refused" or "ok">
  local start end status
  start=$(date +%s)
  while true; do
    status="$(probe || true)"
    if [[ "$2" == "refused" && "$status" == "502" ]] || [[ "$2" == "ok" && "$status" == "$expect_ok" ]]; then break; fi
    sleep 10
  done
  end=$(date +%s)
  log "$1: $((end - start)) seconds (last status $status)"
}
```

**New idea.** `local name=value` declares a variable that exists only inside the function, so it cannot clash with a variable of the same name elsewhere.

**New idea.** `date -u +%H:%M:%S` prints the current time in UTC (`-u`) as hours:minutes:seconds; the `+` begins a format.

**New idea.** `$(( expression ))` calculates with whole numbers and gives the result as text; `(( expression ))` as a command succeeds when the expression is not zero, so `((attempt >= attempts))` is a comparison.

**New idea.** `until command; do ...; done` repeats the block until the command succeeds. `while` is the same with the test reversed.

`wait_for <description> <"refused" or "ok">` measures how long it takes for the app to reach a state.

- `local start end status` declares three variables for use inside the function.
- `start=$(date +%s)` stores the current time as seconds since 1 January 1970 (`+%s`), a plain number that can be subtracted.
- `while true; do ... done` repeats forever, until `break` leaves the loop.
- `status="$(probe || true)"` sends one probe request and stores the status code; `|| true` keeps `set -e` from stopping the script if curl fails.
- The `if` ends the loop when the wanted state is reached: either the second argument is `refused` and the status is `502` (the app returns 502 when a dependency call is denied) **or** the argument is `ok` and the status equals the success status. `&&` joins two tests that must both hold, and `||` between the two `[[ ]]` groups means either group is enough.
- `sleep 10` waits ten seconds between probes.
- After the loop `end=$(date +%s)` and `log` prints the elapsed seconds, `$((end - start))`, with the last status.

**Lines 47 to 49**

```bash
log "removing '$ROLE' at $SCOPE"
az role assignment delete --assignee "$PRINCIPAL" --role "$ROLE" --scope "$SCOPE"
wait_for "removal to first refused request" refused
```

Logs what is removed and where. `az role assignment delete --assignee "$PRINCIPAL" --role "$ROLE" --scope "$SCOPE"` deletes the app identity's role assignment at that one scope. Then `wait_for ... refused` measures the time until the first refused request.

**Lines 51 to 54**

```bash
log "restoring the role"
az role assignment create --assignee-object-id "$PRINCIPAL" --assignee-principal-type ServicePrincipal \
  --role "$ROLE" --scope "$SCOPE" --output none
wait_for "restore to first successful request" ok
```

Restores the role with `az role assignment create`: `--assignee-object-id` names the identity by its object id, `--assignee-principal-type ServicePrincipal` says what kind of identity it is (this saves a directory lookup that can fail just after creation), `--role` and `--scope` as before, and `--output none` prints nothing. The trailing backslash continues the command on the next line. Then `wait_for ... ok` measures the time until the first successful request.

**Lines 56 to 57**

```bash
log "Write both numbers into docs/RUNBOOK.md (propagation table). Now read the denial: scripts/read-denials.sh $TARGET"
log "Note: terraform state still lists this assignment; 'terraform apply' reports no change because the role is back."
```

**New idea.** Terraform's **state** is a file in which it records the real resources it created and their ids. Each run compares the code, the state and reality to decide what to change. It may contain sensitive values, so it is never committed; a *backend* is the place where the state is stored.

Two final reminders printed with `log`: the two measured numbers belong in the propagation table of `docs/RUNBOOK.md`, and the next step is reading the denial with `read-denials.sh`; also, Terraform's state still lists the assignment, and `terraform apply` reports no change because the role has been put back.

#### `scripts/build-and-deploy.sh`

27 lines of code and comments. Each block below quotes consecutive lines of the file, with the line numbers, and explains them.

**Line 1**

```bash
#!/usr/bin/env bash
```



**Lines 2 to 5**

```bash
# Phase 2 (lesson step 4): build the image inside the registry (no local Docker needed), then add the container app.
#   scripts/build-and-deploy.sh                    az acr build (ACR Tasks)
#   BUILD_MODE=local scripts/build-and-deploy.sh   docker build and push, for subscriptions where ACR Tasks is not allowed
#                                                  (some free-trial subscriptions)
```

**New idea.** A **container registry** is a server that stores container images under names and version tags. **Azure Container Registry (ACR)** is Azure's; a service pulls an image from it using an identity that holds the `AcrPull` role.

**New idea.** An Azure **subscription** is the billing container for resources: everything created in it is charged to it, and its settings and access control apply to it. A *tenant* (the organization's identity directory) can hold several subscriptions.

**New idea.** An **environment variable** is a variable that is passed on to every program the script starts. `export NAME` marks a variable that way. Programs use them as settings, for example to find a namespace name or a port.

A comment block explaining phase 2 (lesson step 4): build the image inside the registry, which needs no local Docker, then add the container app. The usages: the default `az acr build` (ACR Tasks, the registry builds the image) and `BUILD_MODE=local` (a variable written before the command is set only for that command) to build with Docker here and push, for subscriptions where ACR Tasks is not allowed (some free-trial subscriptions).

**Lines 6 to 7**

```bash
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
```

`source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"` loads the shared helpers (`log`, `die`, `need`, `require_login`, `tf_out`, `retry`, and the variables `ROOT` and `TF_DIR`) from `lib.sh`, which sits in the same folder as this script.

**Lines 8 to 9**

```bash
need az terraform curl
require_login
```

Requires `az`, `terraform` and `curl`, and an Azure sign-in.

**Lines 11 to 13**

```bash
REGISTRY="$(tf_out registry_name)"
LOGIN_SERVER="$(tf_out registry_login_server)"
IMAGE="$LOGIN_SERVER/azure-secretless-app:$APP_VERSION"
```

**New idea.** **Tags** are name/value labels attached to Azure resources. They change no behavior; they record the owner, project and environment and make cost reports and clean-up possible.

**New idea.** `$(command)` is **command substitution**: bash runs the command and puts its output in place of the `$(...)`. For example `"$(date)"` becomes the current date as text.

`REGISTRY` is the registry's name and `LOGIN_SERVER` its host name, both from Terraform outputs. `IMAGE` is the full image name `<login server>/azure-secretless-app:<version>`, with `APP_VERSION` from `lib.sh` as the tag.

**Line 15**

```bash
if [[ "${BUILD_MODE:-acr}" == "local" ]]; then
```

Starts the local-build branch when `BUILD_MODE` is `local`; `${BUILD_MODE:-acr}` means "the variable, or `acr` if it is not set".

**Lines 16 to 20**

```bash
  need docker
  log "building $IMAGE locally and pushing it"
  az acr login --name "$REGISTRY"
  docker build --platform linux/amd64 --tag "$IMAGE" "$ROOT"
  docker push "$IMAGE"
```

**New idea.** **`docker`** is the command-line program for containers. `docker build` builds an image from a Dockerfile, `docker run` starts a container from an image (`--rm` deletes the container afterwards, `--entrypoint` replaces its start command), and `docker push` uploads an image to a registry.

The local branch: `need docker` requires Docker, `az acr login --name "$REGISTRY"` signs Docker in to the registry with the Azure identity, `docker build --platform linux/amd64 --tag "$IMAGE" "$ROOT"` builds the image for the 64-bit Intel/AMD architecture that Azure runs (important on a Mac with an Arm processor), and `docker push "$IMAGE"` uploads it.

**Lines 21 to 24**

```bash
else
  log "building $IMAGE in $REGISTRY"
  az acr build --registry "$REGISTRY" --image "azure-secretless-app:$APP_VERSION" "$ROOT"
fi
```

The default branch (`else`): `az acr build --registry "$REGISTRY" --image "azure-secretless-app:$APP_VERSION" "$ROOT"` sends the folder to the registry, which builds and stores the image. `fi` ends the `if`.

**Line 26**

```bash
terraform -chdir="$TF_DIR" apply -input=false -auto-approve -var "deploy_app=true" -var "image=$IMAGE"
```

**New idea.** **`terraform`** is the command-line program of Terraform. `terraform -chdir=DIR <command>` runs the command in another folder; `init` downloads the plug-ins; `apply` creates or changes real resources to match the code; `destroy` deletes them; `output -raw NAME` prints one output value with no quotes. `-input=false` means "never stop to ask a question", and `-auto-approve` skips the confirmation question before changes.

Runs `apply` with `-var "deploy_app=true"` and `-var "image=$IMAGE"`, which set two input variables for this run. Phase 1 left `deploy_app` false; now the container app is added, running the image just built.

**Lines 28 to 31**

```bash
URL="$(tf_out app_url)"
log "waiting for $URL/live (a scaled-to-zero app needs a cold start)"
retry 20 10 curl --fail --silent --show-error "$URL/live" >/dev/null
log "app is up: $URL"
```

`URL` is the app's address from a Terraform output. The app scales to zero when idle, so the first request needs a cold start; `retry 20 10 curl --fail --silent --show-error "$URL/live" >/dev/null` calls the `retry` helper: up to 20 attempts, 10 seconds apart, of a request that fails (`--fail`) on an error status. The `log` lines announce the wait and the result.

#### `scripts/docker-smoke.sh`

23 lines of code and comments. Each block below quotes consecutive lines of the file, with the line numbers, and explains them.

**Line 1**

```bash
#!/usr/bin/env bash
```



**Lines 2 to 4**

```bash
# Run the built image with the in-memory backend and call it: proves the image starts as a non-root user,
# answers /live and /health, accepts an upload and refuses a bad name.
#   scripts/docker-smoke.sh <image>
```

A comment block: the script runs the built image with the in-memory backend and calls it, to prove that it starts as a non-root user, answers `/live` and `/health`, accepts an upload and refuses a bad name. Usage: `scripts/docker-smoke.sh <image>`.

**Lines 5 to 7**

```bash
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
need docker curl
```

`source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"` loads the shared helpers (`log`, `die`, `need`, `require_login`, `tf_out`, `retry`, and the variables `ROOT` and `TF_DIR`) from `lib.sh`, which sits in the same folder as this script.
Requires `docker` and `curl`.

**Lines 9 to 11**

```bash
IMAGE="${1:?usage: docker-smoke.sh <image>}"
NAME="secretless-smoke-$$"
trap 'docker rm -f "$NAME" >/dev/null 2>&1 || true' EXIT
```

**New idea.** `trap command SIGNAL` registers a command to run when the script receives that **signal**. A signal is a message the operating system sends to a process: `INT` is sent by Ctrl+C and `TERM` by the request to stop. It is used to clean up when the script is interrupted.

**New idea.** A **process** is one running program, with its own memory and a number (its **pid**). Starting a command starts a process.

`IMAGE` is the first argument, and `${1:?usage: ...}` stops the script with the usage text if it is missing. `NAME="secretless-smoke-$$"` builds a unique container name: `$$` is the process id of this script. `trap '...' EXIT` registers clean-up for when the script ends **for any reason** (`EXIT`): `docker rm -f "$NAME"` force-removes the container, hiding output and ignoring errors.

**Lines 13 to 15**

```bash
docker run -d --name "$NAME" -e BACKEND=memory -p 127.0.0.1::8000 "$IMAGE" >/dev/null
PORT="$(docker port "$NAME" 8000/tcp | head -1 | sed 's/.*://')"
retry 20 1 curl --fail --silent "http://127.0.0.1:$PORT/live" >/dev/null
```

**New idea.** A **port** is a number between 1 and 65535 that tells the computer which program on it should receive a network connection. An address such as `127.0.0.1:8000` means "this computer, port 8000"; `127.0.0.1` is the address a computer uses to talk to itself.

**New idea.** An **IP address** such as `10.10.2.4` identifies a computer on a network. A **CIDR range** such as `10.10.2.0/24` names a block of addresses: the number after the slash says how many leading bits are fixed, so `/24` fixes the first three numbers and leaves 256 addresses. Ranges starting `10.`, `172.16.` to `172.31.` and `192.168.` are *private*: they are not reachable from the public internet.

**New idea.** A **version number** such as `4.81.0` is read as major.minor.patch. A constraint such as `>=4.81` means "4.81 or newer", and Terraform's `~> 4.81` means "4.81 or newer but below 5.0".

**New idea.** A **fake** (or *test double*) is a simple stand-in object used in tests in place of a real service. It behaves like the real one in the ways the test needs, with no network, no account and no cost.

**New idea.** A **pipe** `a | b` connects the output of command `a` to the input of command `b`, so `b` processes what `a` printed.

**New idea.** `sed` edits text as it flows through. `sed -n 's/pattern/replacement/p'` prints (`p`) only the lines where the substitution `s` matched, after replacing the matched part; `\(...\)` marks a group that `\1` in the replacement puts back.

`docker run -d --name "$NAME" -e BACKEND=memory -p 127.0.0.1::8000 "$IMAGE"` starts the container: `-d` detaches it (runs in the background), `--name` names it, `-e BACKEND=memory` sets the environment variable that selects the in-memory fake backend, and `-p 127.0.0.1::8000` publishes container port 8000 on the loopback address with a free port chosen by Docker. `docker port "$NAME" 8000/tcp` prints where the port ended up; `head -1` keeps the first line and `sed 's/.*://'` deletes everything up to the last colon, leaving the port number. `retry 20 1 curl --fail --silent ...` then waits, up to 20 seconds, until `/live` answers.

**Lines 17 to 18**

```bash
log "user inside the container: $(docker exec "$NAME" id -un) (uid $(docker exec "$NAME" id -u))"
[[ "$(docker exec "$NAME" id -u)" != "0" ]] || die "the container runs as root"
```

`docker exec "$NAME" id -un` runs the command `id -un` inside the running container and prints the user name; `id -u` prints the numeric user id. The log line shows both; the next line stops the script if the id is `0` (`root`).

**Lines 20 to 23**

```bash
curl --fail --silent "http://127.0.0.1:$PORT/health"; echo
curl --fail --silent -X POST --data-binary 'hello' "http://127.0.0.1:$PORT/upload/hello.txt"; echo
STATUS="$(curl --silent --output /dev/null --write-out '%{http_code}' -X POST --data-binary x "http://127.0.0.1:$PORT/upload/.hidden")"
[[ "$STATUS" == "400" ]] || die "expected 400 for a bad name, got $STATUS"
```

Calls the routes: `GET /health` and `POST /upload/hello.txt` with the body `hello` (`--data-binary 'hello'`); `; echo` prints a new line after each answer. Then a request that must be refused: uploading a file named `.hidden`, with `--write-out '%{http_code}'` capturing only the status, which has to be `400`.

**Lines 24 to 27**

```bash
docker stop --time 20 "$NAME" >/dev/null
EXIT_CODE="$(docker inspect "$NAME" --format '{{.State.ExitCode}}')"
[[ "$EXIT_CODE" == "0" ]] || die "the container exited with $EXIT_CODE after SIGTERM (expected a graceful 0)"
log "OK: image works, runs as non-root and shuts down gracefully"
```

**New idea.** A **graceful shutdown** lets a program finish the work it has started, close its connections and exit with code 0 when it is asked to stop, instead of being cut off in the middle of a task.

`docker stop --time 20 "$NAME"` sends the stop signal (SIGTERM) and waits up to 20 seconds. `docker inspect "$NAME" --format '{{.State.ExitCode}}'` reads the container's exit code (the text in double braces is a template that picks a field). The test requires `0`, a graceful shutdown. The last line logs success.

#### `scripts/lib.sh`

31 lines of code and comments. Each block below quotes consecutive lines of the file, with the line numbers, and explains them.

**Line 1**

```bash
#!/usr/bin/env bash
```

This script is a **library**: it defines helpers and is not meant to be run on its own.

**Line 2**

```bash
# Shared helpers for the runbook scripts. Source it; do not run it.
```

The comment says what the file is for: shared helpers for the runbook scripts. It is `source`d by them, not run.

**Line 3**

```bash
set -euo pipefail
```



**Line 5**

```bash
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
```

**New idea.** A **variable** is a named piece of text: `NAME=value` sets it (no spaces around `=`) and `$NAME` or `${NAME}` reads it. Always write the read in double quotes, `"$NAME"`, so that spaces in the value are not treated as separators between arguments.

Reading the line from the inside out: `dirname "${BASH_SOURCE[0]}"` is the folder of this file (`scripts/`); adding `/..` means "one folder up", the repository root; `cd <there> && pwd` goes to that folder and prints its full path (`pwd`, "print working directory"), and the outer `$(...)` captures that text into the variable `ROOT`. Every script can then find files relative to the repository root, whatever folder it was started from.

**Line 6**

```bash
TF_DIR="$ROOT/infra/environments/dev"
```

`TF_DIR` is the Terraform environment folder, built from `ROOT`. Scripts use it with `terraform -chdir=` to run Terraform commands there without changing folder.

**Line 7**

```bash
APP_VERSION="$(sed -n 's/^version = "\(.*\)"/\1/p' "$ROOT/pyproject.toml" | head -1)"
```

This line reads the project's version out of `pyproject.toml`. `sed -n 's/^version = "\(.*\)"/\1/p'` looks for the line that starts with `version = "`, keeps only the text between the quotes, and prints just that line; `| head -1` keeps the first match only. The version is used as the image tag, so the tag always equals the package version.

**Line 8**

```bash
export APP_VERSION
```

`export APP_VERSION` makes the variable visible to programs the scripts start.

**Line 10**

```bash
log() { printf '%s %s\n' "$(date -u +%H:%M:%S)" "$*"; }
```

**New idea.** `printf 'format' args` prints text. In the format, `%s` is replaced by the next argument as text and `\n` is a new line; unlike `echo`, `printf` behaves the same on every system.

`log` prints a message with a time stamp in front. `"$(date -u +%H:%M:%S)"` is the current time in UTC; `"$*"` is all the arguments joined into one text. It is used for progress lines such as `12:01:07 registering Microsoft.App`.

**Line 11**

```bash
die() { printf 'error: %s\n' "$*" >&2; exit 1; }
```

**New idea.** A program has two output streams: **standard output** (the normal result) and **standard error** (messages about problems). `>&2` sends a command's output to standard error, so that error messages do not get mixed into the result a caller might capture.

`die` prints `error: <message>` on standard error and then ends the script with status 1 (`exit 1`). Every failed check in the scripts calls it, which gives one uniform error format.

**Lines 13 to 17**

```bash
need() {
  for tool in "$@"; do
    command -v "$tool" >/dev/null || die "$tool is not installed"
  done
}
```

**New idea.** An Azure **region** (such as `westeurope`) is a group of data centers in one geographic area. Where a resource is created decides its latency, its price and which legal rules apply.

**New idea.** `command -v name` prints where the program `name` is installed and succeeds if it exists, fails if it does not. It is the portable way to test whether a tool is available.

**New idea.** `for name in list; do ...; done` runs the commands between `do` and `done` once for each word of the list, with the variable `name` set to that word.

`need` checks that tools are installed. `for tool in "$@"; do ... done` repeats the line for each argument (`"$@"` is every argument as a separate word). `>/dev/null` hides the printed location, and `|| die "... is not installed"` stops the script with a clear message when the tool is missing. Usage: `need az terraform`.

**Lines 19 to 22**

```bash
require_login() {
  need az
  az account show >/dev/null 2>&1 || die "not signed in: run 'az login' first"
}
```

`require_login` checks that the Azure command-line program is installed (`need az`) and that someone is signed in. `az account show` prints the signed-in account and fails when nobody is; `>/dev/null 2>&1` throws away both normal output and error output, because only the success or failure matters here. The message tells the user the fix: `az login`.

**Lines 24 to 25**

```bash
# tf_out <name>: one raw output of the dev environment.
tf_out() { terraform -chdir="$TF_DIR" output -raw "$1"; }
```

A comment line documents the function, then `tf_out` prints one Terraform output of the dev environment. `terraform -chdir="$TF_DIR" output -raw "$1"` runs `terraform output` in the environment folder; `-raw` prints the value without quotes, and `$1` is the name passed to the function (for example `tf_out registry_name`).

**Lines 27 to 37**

```bash
# retry <attempts> <sleep seconds> <command...>: role assignments take minutes to apply, so data-plane calls retry.
retry() {
  local attempts=$1 pause=$2 attempt=1
  shift 2
  until "$@"; do
    if ((attempt >= attempts)); then return 1; fi
    log "attempt $attempt of $attempts failed; waiting ${pause}s for the role assignment to take effect"
    sleep "$pause"
    attempt=$((attempt + 1))
  done
}
```

**New idea.** `sleep N` pauses the script for N seconds.

`retry <attempts> <seconds> <command...>` runs a command until it succeeds, up to a maximum. It exists because a new Azure role assignment can take several minutes to take effect, so the first data calls may be refused with a permission error that disappears by itself.

- `local attempts=$1 pause=$2 attempt=1` sets three variables: the maximum number of attempts (first argument), the pause (second argument) and the attempt counter, starting at 1. 
- `shift 2` removes the first two arguments from the list, so that `"$@"` is now only the command to run.
- `until "$@"; do ... done` runs the command and repeats the block as long as it fails. 
- `if ((attempt >= attempts)); then return 1; fi` gives up (leaves the function with status 1) when the last attempt has failed. 
- `log "attempt ... failed; waiting ${pause}s ..."` tells the user what is happening.
- `sleep "$pause"` waits.
- `attempt=$((attempt + 1))` adds one to the counter.

#### `scripts/prove-key-access-closed.sh`

12 lines of code and comments. Each block below quotes consecutive lines of the file, with the line numbers, and explains them.

**Line 1**

```bash
#!/usr/bin/env bash
```



**Line 2**

```bash
# Step 2 "Done when": an attempt to use a storage account key fails because shared key access is off.
```

A comment: lesson step 2's check that an attempt to use a storage account **key** fails because shared key access is switched off.

**Lines 3 to 6**

```bash
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
need az terraform
require_login
```

`source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"` loads the shared helpers (`log`, `die`, `need`, `require_login`, `tf_out`, `retry`, and the variables `ROOT` and `TF_DIR`) from `lib.sh`, which sits in the same folder as this script.
Requires `az` and `terraform` and an Azure sign-in.

**Lines 8 to 11**

```bash
ACCOUNT="$(tf_out storage_account_name)"
if output="$(az storage container list --account-name "$ACCOUNT" --auth-mode key 2>&1)"; then
  die "listing containers with an account key SUCCEEDED: shared key access is not disabled"
fi
```

`ACCOUNT` is the storage account name from a Terraform output. The `if` runs a command and tests whether it succeeds: `output="$(az storage container list --account-name "$ACCOUNT" --auth-mode key 2>&1)"` tries to list the containers using the account key (`--auth-mode key`) and stores everything it printed, errors included (`2>&1`). If it **succeeds**, the account still accepts keys, which is the failure the script is looking for, so it calls `die`.

**Lines 12 to 13**

```bash
grep -q "KeyBasedAuthenticationNotPermitted" <<<"$output" || die "the key request failed, but not with KeyBasedAuthenticationNotPermitted: $output"
log "OK: --auth-mode key is refused with KeyBasedAuthenticationNotPermitted"
```

The command was refused, as hoped. The script now checks that the reason is the right one: the error text must contain `KeyBasedAuthenticationNotPermitted`, Azure's name for "shared key access is off" (`<<<` feeds the stored text to `grep`, `-q` prints nothing). A failure for another reason (for example a typo) would make the test pass for the wrong reason, so it is rejected. The last line logs success.

#### `scripts/provision.sh`

34 lines of code and comments. Each block below quotes consecutive lines of the file, with the line numbers, and explains them.

**Line 1**

```bash
#!/usr/bin/env bash
```



**Lines 2 to 5**

```bash
# Phase 1 (lesson steps 1 to 3): resource group, workspace, identities, vault, storage, registry, role assignments,
# budget. The container app comes in phase 2 (build-and-deploy.sh) because its image must exist first.
#
#   BUDGET_EMAIL=you@example.com scripts/provision.sh [--yes]
```

**New idea.** An Azure **budget** watches the spending of a subscription and e-mails people when it passes a threshold such as 80 or 100 percent. It alerts; it does not stop anything from running.

A comment block. Phase 1 (lesson steps 1 to 3) creates the resource group, workspace, identities, vault, storage, registry, role assignments and budget. The container app comes in phase 2 (`build-and-deploy.sh`), because its image must exist first. The last line shows the usage: `BUDGET_EMAIL=you@example.com scripts/provision.sh [--yes]`. A variable written before the command is set only for that command, and `[--yes]` in brackets marks an optional argument.

**Lines 6 to 7**

```bash
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
```

`source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"` loads the shared helpers (`log`, `die`, `need`, `require_login`, `tf_out`, `retry`, and the variables `ROOT` and `TF_DIR`) from `lib.sh`, which sits in the same folder as this script.

**Lines 8 to 9**

```bash
need az terraform
require_login
```

Requires `az` and `terraform` and an Azure sign-in.

**Lines 11 to 12**

```bash
AUTO_APPROVE=""
[[ "${1:-}" == "--yes" ]] && AUTO_APPROVE="-auto-approve"
```

`AUTO_APPROVE=""` creates the variable with an empty value. The next line is a test followed by `&&`: `[[ "${1:-}" == "--yes" ]]` is true when the first argument of the script is exactly `--yes`, and only then does `AUTO_APPROVE="-auto-approve"` run. So the variable holds either nothing or the Terraform option that skips the confirmation question.

**Lines 14 to 19**

```bash
# Register the resource providers once, so the Terraform plan never changes subscription-wide settings itself.
for provider in Microsoft.App Microsoft.ContainerRegistry Microsoft.Consumption Microsoft.Insights \
  Microsoft.KeyVault Microsoft.ManagedIdentity Microsoft.OperationalInsights Microsoft.Storage; do
  log "registering $provider"
  az provider register --namespace "$provider" --wait >/dev/null
done
```

A comment says why this block exists: the Azure **resource providers** are registered once, here, so that the Terraform plan never changes subscription-wide settings by itself. A resource provider is the part of Azure that owns one kind of resource (for example `Microsoft.KeyVault`); a subscription must have it registered before resources of that kind can be created.

The `for provider in ...; do ... done` loop takes each of the eight provider names in turn (the backslash at the end of the first line continues the list on the next line). For each one `log` prints what is happening, and `az provider register --namespace "$provider" --wait` registers it and waits until Azure has finished; `>/dev/null` hides the output.

**Line 21**

```bash
TFVARS="$TF_DIR/terraform.tfvars"
```

`TFVARS` holds the path of the file `terraform.tfvars` in the environment folder. A `.tfvars` file assigns values to Terraform's input variables.

**Lines 22 to 24**

```bash
if [[ ! -f "$TFVARS" ]]; then
  [[ -n "${BUDGET_EMAIL:-}" ]] || die "set BUDGET_EMAIL=you@example.com (lesson step 1: a budget alert), or write $TFVARS yourself"
  log "writing $TFVARS from your az session (it holds ids, so it is git-ignored)"
```

**New idea.** **git** is the version-control system that records every change to the project's files as a numbered commit, so any earlier state can be recovered and changes can be reviewed. Files listed in `.gitignore` are never recorded.

`if [[ ! -f "$TFVARS" ]]; then` runs the block only when the file does **not** exist (`-f` tests for a regular file, `!` negates). Inside it, line 23 requires that `BUDGET_EMAIL` is set and not empty (`-n` tests for a non-empty text) and stops with an explanation otherwise. Line 24 logs that the file is about to be written from the Azure session, and that it is excluded from git because it holds ids.

**Lines 25 to 31**

```bash
  cat >"$TFVARS" <<TFVARS_EOF
subscription_id       = "$(az account show --query id --output tsv)"
tenant_id             = "$(az account show --query tenantId --output tsv)"
deployer_object_id    = "$(az ad signed-in-user show --query id --output tsv)"
budget_contact_emails = ["$BUDGET_EMAIL"]
budget_start_date     = "$(date -u +%Y-%m-01T00:00:00Z)"
TFVARS_EOF
```

**New idea.** A **here document** `<<MARKER ... MARKER` feeds the lines between the marker words to a command as its input, with variables and `$(...)` expanded inside. `cat >file <<MARKER` therefore writes those lines into the file.

`cat >"$TFVARS" <<TFVARS_EOF` writes everything up to the line `TFVARS_EOF` into the file. The lines in between are Terraform variable assignments in which `$(...)` is replaced before writing: `az account show --query id --output tsv` prints the subscription id, `--query tenantId` the tenant id, and `az ad signed-in-user show --query id` the object id of the signed-in person (who becomes the deployer allowed to set the secret). `BUDGET_EMAIL` goes into `budget_contact_emails`, and `date -u +%Y-%m-01T00:00:00Z` gives the first day of the current month as the budget start date. These values are personal, so the file is created at run time and never committed.

**Line 32**

```bash
fi
```

`fi` ends the `if` block.

**Lines 34 to 35**

```bash
terraform -chdir="$TF_DIR" init -input=false
terraform -chdir="$TF_DIR" apply -input=false $AUTO_APPROVE
```

Two Terraform commands, both run in the environment folder: `init` downloads the provider plug-ins, and `apply` creates the resources. `$AUTO_APPROVE` is left unquoted on purpose, so that when it is empty it disappears and when it holds `-auto-approve` it becomes that option.

**Lines 37 to 39**

```bash
"$ROOT/scripts/seed-secret.sh"
"$ROOT/scripts/prove-key-access-closed.sh"
log "phase 1 done. Next: scripts/build-and-deploy.sh"
```

Runs the two follow-up scripts, `seed-secret.sh` (puts the demo secret in the vault) and `prove-key-access-closed.sh` (shows that account keys are refused), then logs that phase 1 is done and what comes next.

#### `scripts/read-denials.sh`

29 lines of code and comments. Each block below quotes consecutive lines of the file, with the line numbers, and explains them.

**Line 1**

```bash
#!/usr/bin/env bash
```



**Lines 2 to 4**

```bash
# Step 5 "Done when": find the denial in the logs, with the identity and the missing permission named.
# Logs reach the workspace a few minutes after the event. The queries are the ones in docs/RUNBOOK.md.
#   scripts/read-denials.sh blob | vault | app
```

A comment block: lesson step 5. Find the denial in the logs, with the identity and the missing permission named. Logs reach the workspace a few minutes after the event. The queries are the ones in `docs/RUNBOOK.md`. Usage: `scripts/read-denials.sh blob | vault | app`.

**Lines 5 to 8**

```bash
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
need az terraform
require_login
```

`source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"` loads the shared helpers (`log`, `die`, `need`, `require_login`, `tf_out`, `retry`, and the variables `ROOT` and `TF_DIR`) from `lib.sh`, which sits in the same folder as this script.
Requires `az` and `terraform` and an Azure sign-in.

**Line 10**

```bash
WORKSPACE="$(tf_out log_analytics_customer_id)"
```

**New idea.** **Log Analytics** is Azure's store for logs and metrics, queried with the Kusto Query Language (KQL). A *diagnostic setting* tells a resource to send its logs there, so that, for example, every refused request to a vault can be found afterwards.

`WORKSPACE` is the customer id of the Log Analytics workspace, the identifier that queries need, from a Terraform output.

**Lines 11 to 16**

```bash
case "${1:-}" in
  blob)
    QUERY='StorageBlobLogs
| where StatusCode == 403
| project TimeGenerated, OperationName, StatusText, RequesterObjectId, AuthenticationType, Uri
| order by TimeGenerated desc | take 10' ;;
```

`case "${1:-}" in` picks a block by the first argument. In the `blob` branch `QUERY` holds a **KQL** (Kusto Query Language) query in single quotes, so that nothing inside is expanded. KQL reads left to right through `|` steps: `StorageBlobLogs` is the table of blob-storage logs; `where StatusCode == 403` keeps the requests that were refused (403, "forbidden"); `project ...` chooses the columns to show, among them the caller's object id (`RequesterObjectId`) and the kind of authentication; `order by TimeGenerated desc` puts the newest first and `take 10` keeps ten rows. The `;;` ends the branch.

**Lines 17 to 21**

```bash
  vault)
    QUERY='AzureDiagnostics
| where ResourceProvider == "MICROSOFT.KEYVAULT" and httpStatusCode_d == 403
| project TimeGenerated, OperationName, ResultSignature, identity_claim_oid_g, requestUri_s, CallerIPAddress
| order by TimeGenerated desc | take 10' ;;
```

The `vault` branch: the table is `AzureDiagnostics`, which holds Key Vault audit events together with other resources' diagnostics, so the query keeps the rows where `ResourceProvider == "MICROSOFT.KEYVAULT"` and the HTTP status `httpStatusCode_d == 403`, and shows the caller's object id (`identity_claim_oid_g`), the address and the caller IP.

**Lines 22 to 26**

```bash
  app)
    QUERY='ContainerAppConsoleLogs_CL
| where Log_s has "access denied"
| project TimeGenerated, Log_s
| order by TimeGenerated desc | take 10' ;;
```

The `app` branch: `ContainerAppConsoleLogs_CL` holds what the container printed. The query keeps the lines that contain the text `access denied` (`has`), which the app writes when a call to Azure is refused.

**Lines 27 to 28**

```bash
  *) die "usage: $0 blob|vault|app" ;;
esac
```

`*) die ... ;;` is the branch for anything else (a usage message); `esac` ends the `case`.

**Lines 30 to 31**

```bash
log "the app identity's object id is $(tf_out app_identity_principal_id); it should appear as the caller"
az monitor log-analytics query --workspace "$WORKSPACE" --analytics-query "$QUERY" --output table
```

Logs the object id of the app identity: it should appear as the caller in the results. Then `az monitor log-analytics query --workspace ... --analytics-query "$QUERY" --output table` runs the query in the workspace and prints a table.

#### `scripts/seed-secret.sh`

13 lines of code and comments. Each block below quotes consecutive lines of the file, with the line numbers, and explains them.

**Line 1**

```bash
#!/usr/bin/env bash
```



**Lines 2 to 3**

```bash
# Step 2: put the partner key in the vault. The value never enters Terraform state.
#   PARTNER_API_KEY=... scripts/seed-secret.sh        (default: the lesson's demo value)
```

A comment block: lesson step 2. The partner key is put in the vault by this script, so its value never enters Terraform state. Usage: `PARTNER_API_KEY=... scripts/seed-secret.sh`, and by default the lesson's demo value is used.

**Lines 4 to 7**

```bash
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
need az terraform
require_login
```

`source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"` loads the shared helpers (`log`, `die`, `need`, `require_login`, `tf_out`, `retry`, and the variables `ROOT` and `TF_DIR`) from `lib.sh`, which sits in the same folder as this script.
Requires `az` and `terraform` and an Azure sign-in.

**Lines 9 to 10**

```bash
VAULT="$(tf_out key_vault_name)"
VALUE="${PARTNER_API_KEY:-demo-value-123}"
```

`VAULT` is the vault name from a Terraform output. `VALUE="${PARTNER_API_KEY:-demo-value-123}"` is the secret value: the environment variable if set, otherwise a harmless demo value.

**Lines 12 to 15**

```bash
# The deployer's Secrets Officer role was assigned seconds ago; Owner alone cannot write secrets, and the role can take
# a few minutes to apply, so retry on 403.
retry 12 30 az keyvault secret set --vault-name "$VAULT" --name partner-api-key --value "$VALUE" --output none
log "secret partner-api-key set in $VAULT (length ${#VALUE})"
```

The comment explains why a retry is needed: the deployer's Secrets Officer role was assigned seconds ago, Owner alone cannot write secrets, and a role can take a few minutes to apply, so a 403 (refused) is retried. `retry 12 30 az keyvault secret set --vault-name ... --name partner-api-key --value ... --output none` tries up to 12 times, 30 seconds apart, to store the secret under the name `partner-api-key`. The last line logs success with the length of the value (`${#VALUE}` is its number of characters), never the value itself.

#### `scripts/smoke.sh`

23 lines of code and comments. Each block below quotes consecutive lines of the file, with the line numbers, and explains them.

**Line 1**

```bash
#!/usr/bin/env bash
```



**Line 2**

```bash
# Steps 3 and 4 "Done when": exactly two narrow role assignments, a working app, an upload in the container.
```

A comment: lesson steps 3 and 4. The checks: exactly two narrow role assignments, a working app, an upload into the container.

**Lines 3 to 6**

```bash
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
need az terraform curl
require_login
```

`source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"` loads the shared helpers (`log`, `die`, `need`, `require_login`, `tf_out`, `retry`, and the variables `ROOT` and `TF_DIR`) from `lib.sh`, which sits in the same folder as this script.
Requires `az`, `terraform` and `curl`, and an Azure sign-in.

**Lines 8 to 11**

```bash
URL="$(tf_out app_url)"
PRINCIPAL="$(tf_out app_identity_principal_id)"
ACCOUNT="$(tf_out storage_account_name)"
CONTAINER="$(tf_out container_name)"
```

Four values from Terraform outputs: the app's address, the object id of the app identity, the storage account and the container.

**Lines 13 to 16**

```bash
log "role assignments of the app identity (exactly two, each on one resource)"
az role assignment list --assignee "$PRINCIPAL" --all --query '[].{role:roleDefinitionName, scope:scope}' --output table
COUNT="$(az role assignment list --assignee "$PRINCIPAL" --all --query 'length(@)' --output tsv)"
[[ "$COUNT" == "2" ]] || die "expected 2 role assignments, found $COUNT"
```

Lists the app identity's role assignments as a table: `az role assignment list --assignee ... --all --query '[].{role:roleDefinitionName, scope:scope}'` takes every entry (`[]`) and keeps two fields. The second command counts them with the query `length(@)` (`@` means the whole result). The test stops the script unless there are exactly two assignments, one per resource the app needs.

**Lines 18 to 19**

```bash
log "GET /health"
curl --fail --silent --show-error "$URL/health"; echo
```

Calls `GET /health` on the deployed app (`--fail` turns an error status into a failure, `--show-error` still prints the error message while `--silent` hides the progress meter). `; echo` prints a new line after the answer.

**Lines 21 to 25**

```bash
FILE="$(mktemp)"
trap 'rm -f "$FILE"' EXIT
echo "hello from the secretless app" >"$FILE"
log "POST /upload/hello.txt"
curl --fail --silent --show-error -X POST --data-binary "@$FILE" "$URL/upload/hello.txt"; echo
```

**New idea.** `mktemp` creates a uniquely named temporary file or folder and prints its path.

`FILE="$(mktemp)"` creates a temporary file, and `trap 'rm -f "$FILE"' EXIT` deletes it when the script ends, however it ends. `echo "hello ..." >"$FILE"` writes a line into it. Then `POST /upload/hello.txt` sends the file: `--data-binary "@$FILE"` uses the file's content as the request body (the `@` means "from this file").

**Lines 27 to 28**

```bash
log "blobs in the container (listed with your own login, no key)"
az storage blob list --account-name "$ACCOUNT" --container-name "$CONTAINER" --auth-mode login --query '[].name' --output json
```

Lists the blobs (files) in the container, using your own login and no key: `--auth-mode login` uses the Azure sign-in, `--query '[].name'` keeps only the names and `--output json` prints them as JSON.

#### `scripts/teardown.sh`

26 lines of code and comments. Each block below quotes consecutive lines of the file, with the line numbers, and explains them.

**Line 1**

```bash
#!/usr/bin/env bash
```



**Lines 2 to 3**

```bash
# Step 6: delete everything, then look at the soft-deleted vault and decide whether to purge it.
#   scripts/teardown.sh [--yes]
```

A comment block: lesson step 6. Delete everything, then look at the soft-deleted vault and decide whether to purge it. Usage: `scripts/teardown.sh [--yes]`.

**Lines 4 to 7**

```bash
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
need az terraform
require_login
```

`source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"` loads the shared helpers (`log`, `die`, `need`, `require_login`, `tf_out`, `retry`, and the variables `ROOT` and `TF_DIR`) from `lib.sh`, which sits in the same folder as this script.
Requires `az` and `terraform` and an Azure sign-in.

**Lines 9 to 10**

```bash
AUTO_APPROVE=""
[[ "${1:-}" == "--yes" ]] && AUTO_APPROVE="-auto-approve"
```

Sets `AUTO_APPROVE` to `-auto-approve` only when the first argument is `--yes`; otherwise Terraform asks for confirmation.

**Lines 12 to 13**

```bash
RG="$(tf_out resource_group_name)"
VAULT="$(tf_out key_vault_name)"
```

Reads the resource group and vault names first (they cannot be read after the destroy).

**Line 15**

```bash
terraform -chdir="$TF_DIR" destroy -input=false $AUTO_APPROVE   # also removes the subscription-scoped budget
```

`terraform destroy` deletes every resource Terraform created, including the subscription-level budget (the trailing comment says so).

**Lines 17 to 19**

```bash
log "resource group $RG exists? -> $(az group exists --name "$RG")"
log "soft-deleted vaults (a deleted vault keeps its name reserved until scheduledPurgeDate):"
az keyvault list-deleted --query "[?name=='$VAULT'].{name:name, deleted:properties.deletionDate, purgeDate:properties.scheduledPurgeDate, purgeProtection:properties.purgeProtectionEnabled}" --output table
```

Logs whether the resource group still exists (`az group exists` prints `true` or `false`), then lists the soft-deleted vaults whose name equals this vault. A vault that is deleted is **soft-deleted**: it is kept, recoverable, for a retention period, and its name stays reserved. The `--query` is a JMESPath filter `[?name=='...']` that keeps only this vault and renames four of its fields for display: deletion date, scheduled purge date and whether purge protection is on.

**Lines 21 to 31**

```bash
PROTECTED="$(az keyvault list-deleted --query "[?name=='$VAULT'].properties.purgeProtectionEnabled | [0]" --output tsv)"
if [[ "$PROTECTED" == "true" ]]; then
  log "purge protection is on: the name stays reserved until the date above and cannot be purged"
elif [[ -n "$PROTECTED" ]]; then
  log "purge protection is off: purging frees the name now"
  if [[ -n "$AUTO_APPROVE" ]]; then
    az keyvault purge --name "$VAULT"
  else
    log "run: az keyvault purge --name $VAULT"
  fi
fi
```

`PROTECTED` is `true`, `false` or empty (not found), taken from the same list. The `if` chain:

- `true`: purge protection is on, so the name stays reserved until the date shown and cannot be purged.
- `elif [[ -n "$PROTECTED" ]]`: it is not empty, so it is `false`: purging would free the name now. Then, if `--yes` was given (`AUTO_APPROVE` is not empty) the script runs `az keyvault purge --name "$VAULT"`; otherwise it only prints that command.
- When it is empty, the vault was not found and nothing is printed.

## Try it yourself

Ask Bash to parse a script without running it.

```bash
bash -n scripts/lib.sh && echo 'syntax ok'
```

You should see something like this:

```text
syntax ok
```

Check the system Bash (3.2) can parse a script.

```bash
/bin/bash -n scripts/provision.sh && echo 'syntax ok on the Bash that macOS ships'
```

You should see something like this:

```text
syntax ok on the Bash that macOS ships
```

Source the helpers and use them.

```bash
bash -c 'source scripts/lib.sh; log hello; echo "version: $APP_VERSION"; need bash && echo found; need no-such-tool; echo "exit: $?"'
```

You should see something like this:

```text
11:30:45 hello
version: 0.1.0
found
error: no-such-tool is not installed
```

Watch `retry` call a flaky command until it works.

```bash
bash -c 'source scripts/lib.sh; n=0; flaky() { n=$((n+1)); [ $n -ge 3 ]; }; retry 5 0 flaky && echo "succeeded after $n tries"'
```

You should see something like this:

```text
11:30:47 attempt 1 of 5 failed; waiting 0s for the role assignment to take effect
11:30:47 attempt 2 of 5 failed; waiting 0s for the role assignment to take effect
succeeded after 3 tries
```

## Mistakes people make

- Leaving variables unquoted. A path with a space becomes two words.
- Forgetting `set -euo pipefail`, so a failed step is ignored and the script carries on.
- Parsing `ls` output. Use globs (`for f in dir/*.sh`).
- Using Bash 4 features on a Mac with Bash 3.2. Here `shellcheck` and `/bin/bash -n` are run to catch that.
- Putting a secret in a command line, where other users can see it with `ps`. Scripts here read secrets from the environment and never print them.

## Check yourself

1. **What does an exit code of 0 mean?**
   Answer: The command succeeded.

2. **What does `set -euo pipefail` do?**
   Answer: Stops on the first error, treats unset variables as errors, and makes a pipe fail if any part fails.

3. **Why quote `"$VAR"`?**
   Answer: So spaces in the value do not split it into several arguments.

4. **What does `$(...)` do?**
   Answer: Runs the command inside and replaces itself with its output.

5. **What does `trap '...' EXIT` do?**
   Answer: Runs the given command when the script ends, success or failure.

## Further reading

- Bash reference manual (the shell scripts are written for Bash 3.2 and newer): https://www.gnu.org/software/bash/manual/bash.html
- Shell parameter expansion: https://www.gnu.org/software/bash/manual/html_node/Shell-Parameter-Expansion.html
