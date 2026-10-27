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
