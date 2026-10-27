# curl and jq

*Call the deployed app and inspect Azure's JSON in the scripts. Pinned here: curl 8.7, jq 1.6.*

## What it is

`curl` is a command-line program that makes web requests and prints the answer. `jq` reads JSON from its input and picks out or reshapes the parts you ask for. Together they let a script call a web endpoint and check what came back.

## Why this repository uses it

After deployment the lesson asks you to call `/health` and `/upload`, and to read the app's configuration. `curl` makes the calls and `jq` reads the JSON that `az` returns.

## Where it appears

| File | What it does with it |
|---|---|
| `scripts/smoke.sh` | `curl` calls the health and upload routes. |
| `scripts/break-and-measure.sh` | `curl` prints only the HTTP status. |
| `scripts/build-and-deploy.sh` | Waits for `/live`. |
| `scripts/audit-config.sh` | `jq` lists environment variables and counts secrets. |
| `scripts/docker-smoke.sh` | Calls the container. |

## How it works underneath

`curl URL` sends an HTTP GET. `-X POST` changes the method, `--data-binary @file` sends a file as the body, `--silent` hides the progress meter, `--fail` makes curl exit non-zero on an HTTP error (4xx, 5xx), `--output /dev/null --write-out '%{http_code}'` prints only the status code.

`jq` takes a **filter**. `.a.b` descends into keys; `.items[]` walks an array; `-r` prints raw text without quotes; `// "x"` gives a default when a value is null.

## Walkthrough of this repository's use

```bash
log "GET /health"
curl --fail --silent --show-error "$URL/health"; echo

FILE="$(mktemp)"
trap 'rm -f "$FILE"' EXIT
echo "hello from the secretless app" >"$FILE"
log "POST /upload/hello.txt"
curl --fail --silent --show-error -X POST --data-binary "@$FILE" "$URL/upload/hello.txt"; echo
```

`--fail` makes curl exit with an error on an HTTP error status. `--silent` hides the progress meter and `--show-error` still prints errors. `-X POST --data-binary "@$FILE"` sends the file's bytes as the body (`@` means "read from this file"). `mktemp` makes a temporary file and the `trap ... EXIT` removes it.

```bash
    probe() { curl --silent --output /dev/null --write-out '%{http_code}' -X POST --data-binary "probe" "$URL/upload/probe.txt"; }
```

`--output /dev/null` discards the body and `--write-out '%{http_code}'` prints only the status number, so the function returns `201` or `502`.

```bash
jq -r '.properties.template.containers[].env[] | "\(.name)=\(.value // "<secretRef " + (.secretRef // "") + ">")"' <<<"$CONFIG"
```

`jq -r` prints raw text. `.properties.template.containers[].env[]` walks every environment variable of every container. `"\(.name)=\(.value // ...)"` builds the text `NAME=value`, and `//` gives a fallback when a value is missing (a variable that points at a secret would show `secretRef`).

## Try it yourself

Check the tools exist.

```bash
curl --version | head -1; jq --version
```

You should see something like this:

```text
curl 8.7.1 (x86_64-apple-darwin25.0) libcurl/8.7.1 (SecureTransport) LibreSSL/3.3.6 zlib/1.2.12 nghttp2/1.68.1
jq-1.6
```

Count the elements of an empty array, as `audit-config.sh` does.

```bash
echo '{"properties":{"configuration":{"secrets":[]}}}' | jq -r '.properties.configuration.secrets | length'
```

You should see something like this:

```text
0
```

Use the `//` fallback.

```bash
echo '{"a":[{"n":"X","v":1},{"n":"Y"}]}' | jq -r '.a[] | "\(.n)=\(.v // "none")"'
```

You should see something like this:

```text
X=1
Y=none
```

## Mistakes people make

- Forgetting `--fail`, so a 500 looks like success.
- Printing a response that may hold a secret. The health route here returns only a length.
- Parsing JSON with grep or sed instead of `jq`.
- Quoting: a `$` inside double quotes is expanded by the shell, not `jq`. Use single quotes for filters.
- No timeout on `curl` in a script; wrap it in the `retry` helper or use `--max-time`.

## Check yourself

1. **What does `curl --fail` change?**
   Answer: A 4xx or 5xx answer makes curl exit with a failure code.

2. **How do you print only the HTTP status?**
   Answer: `curl --silent --output /dev/null --write-out '%{http_code}' URL`.

3. **What does `jq -r` do?**
   Answer: Prints strings without the surrounding quotes.

4. **What does `.items[]` do in `jq`?**
   Answer: Walks every element of the `items` array.

5. **Why use single quotes around a `jq` filter?**
   Answer: So the shell does not change `$` and other characters in it.

## Further reading

- curl 8: https://curl.se/docs/manpage.html
- jq 1.6 manual: https://jqlang.github.io/jq/manual/v1.6/
