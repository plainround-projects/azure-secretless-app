# pytest and coverage

*Runs the tests and measures how much code they run. Pinned here: pytest 9.1.1, pytest-cov 7.1.0, coverage 7.17.0.*

## What it is

pytest is a tool that finds and runs the tests of a Python project. A **test** is a function whose name starts with `test_`. It runs some code and uses `assert` to say what must be true. If an `assert` is false, pytest reports a failure and shows both sides of the comparison. **Coverage** (the `pytest-cov` plugin, which uses the `coverage` library) measures which lines of the code the tests ran.

## Why this repository uses it

The lesson's app has no automated tests in its starting point. This repository adds tests at three levels so the behavior can be checked without Azure: unit tests with in-memory fakes, an end-to-end test that starts the real server, and a live test that is skipped unless you have a subscription.

## Where it appears

| File | What it does with it |
|---|---|
| `tests/unit/` | Unit tests, one folder per layer. |
| `tests/e2e/test_server.py` | Starts the real gunicorn and sends requests. |
| `tests/integration/test_azure_live.py` | The live Azure test, skipped by default. |
| `tests/conftest.py` | Shared fixtures. |
| `pyproject.toml` | pytest and coverage settings. |
| `Makefile` | `make test` runs pytest with coverage and checks the 95 percent bar. |

## How it works underneath

pytest walks the folders named in `testpaths`, imports every file called `test_*.py` and collects the functions called `test_*`. For each one it runs the function. A test that raises an exception, or fails an `assert`, is a failure; a test that finishes is a pass.

A **fixture** is a function marked `@pytest.fixture`. When a test lists the fixture's name as a parameter, pytest calls the fixture first and passes in the result. That is how tests get a fresh temporary file or a fake object without repeating code.

A **marker** (`@pytest.mark.something`) labels tests so you can choose them (`-m e2e`). `--strict-markers` makes an unknown label an error, which catches typos.

With `--cov=package`, coverage watches the program while the tests run, records every line and branch that executed, and prints a table of what was missed.

## Walkthrough of this repository's use

### The settings

```toml
[tool.pytest.ini_options]
```

```toml
[tool.coverage.run]
source = ["secretless_app"]
branch = true

[tool.coverage.report]
show_missing = true
skip_covered = false
```

`testpaths` is where pytest looks. `addopts = "-ra --strict-markers"` adds options to every run: `-ra` prints a summary of every skipped or failed test, `--strict-markers` rejects unknown markers. `markers` declares `azure` and `e2e` with a description. `branch = true` makes coverage count both outcomes of every `if`, not only whether the line ran. `show_missing` prints the line numbers that were not run.

### A fixture

```python
@pytest.fixture
def blobs() -> InMemoryBlobStore:
    return InMemoryBlobStore()


@pytest.fixture
def services(blobs: InMemoryBlobStore) -> Services:
    secrets = InMemorySecretStore({SECRET_NAME: SECRET_VALUE})
    return Services(CheckHealth(secrets, SECRET_NAME), SaveUpload(blobs, max_bytes=1024))
```

The `blobs` fixture returns a fresh in-memory blob store for each test. The `services` fixture asks for `blobs`, so pytest builds `blobs` first, and builds `Services` around it with the in-memory secret store. Test functions declare `services` or `blobs` as parameters and receive them.

### A test that reads like a sentence

```python
def test_an_upload_at_the_limit_is_accepted_and_one_byte_over_is_refused():
    use_case = SaveUpload(InMemoryBlobStore(), max_bytes=4)
    use_case.run("ok.bin", b"1234")
    with pytest.raises(UploadTooLargeError):
        use_case.run("big.bin", b"12345")
```

The test name says the behavior. `with pytest.raises(UploadTooLargeError):` passes only if the block raises that error.

### A parametrized test

```python
@pytest.mark.parametrize("value", ["hello.txt", "a", "Report_2026-10.csv", "x" * 128, "v1.2.3.tar.gz"])
def test_a_plain_file_name_is_accepted(value):
    assert BlobName(value).value == value
```

`parametrize` runs one test function once per listed value, each reported separately. Eleven bad names become eleven checks.

### The end-to-end marker

```python
pytestmark = pytest.mark.e2e
```

`pytestmark` applies the `e2e` marker to every test in the file, so `make test-e2e` can select them with `-m e2e`.

### The coverage bar

```make
test: $(STAMP) ## unit and end-to-end tests with coverage (no Azure needed)
	$(PY) -m pytest tests/unit tests/e2e --cov=secretless_app --cov-report=term
	$(PY) -m coverage report --include='src/secretless_app/domain/*,src/secretless_app/application/*' --fail-under=95
```

`--cov=secretless_app` measures the package. The second command reports only the `domain` and `application` folders and fails if they are below 95 percent. Those layers hold the rules, so they carry the bar; they are at 100 percent.

## Try it yourself

Run the domain tests.

```bash
.venv/bin/python -m pytest tests/unit/domain -q -p no:cacheprovider
```

You should see something like this:

```text
..................                                                       [100%]
18 passed in 0.01s
```

See how many unit tests pytest collects.

```bash
.venv/bin/python -m pytest tests/unit -q -p no:cacheprovider --collect-only | tail -3
```

You should see something like this:

```text
tests/unit/interfaces/test_http.py::test_every_request_is_logged_with_status_and_duration

59 tests collected in 2.49s
```

Run the unit and end-to-end tests with a coverage report.

```bash
.venv/bin/python -m pytest tests/unit tests/e2e -q -p no:cacheprovider --cov=secretless_app --cov-report=term | tail -8
```

You should see something like this:

```text
src/secretless_app/infrastructure/settings.py             51      1     18      1    97%   75
src/secretless_app/infrastructure/wiring.py               17      1      4      1    90%   21
src/secretless_app/interfaces/__init__.py                  0      0      0      0   100%
src/secretless_app/interfaces/http.py                     54      1      0      0    98%   49
src/secretless_app/interfaces/wsgi.py                     10     10      0      0     0%   3-17
--------------------------------------------------------------------------------------------------
TOTAL                                                    302     13     46      2    96%
63 passed in 109.52s (0:01:49)
```

## Mistakes people make

- Tests that depend on each other's order or leave files behind. Here every test gets its own temporary folder (`tmp_path`).
- Asserting too little: a test that only checks that nothing crashed. The test names here say the behavior they check.
- Sleeping in tests to wait for time to pass. The code takes a clock as an input and the tests use a fake clock, so no test waits.
- Chasing 100 percent coverage everywhere. This repository sets the bar where it matters (the domain and application layers) and reports the rest.
- Forgetting the marker on slow tests. Slow tests are marked and live in their own folder.

## Check yourself

1. **How does pytest know a function is a test?**
   Answer: Its name starts with `test_` and it is in a file called `test_*.py` under a folder listed in `testpaths`.

2. **What does a fixture give a test?**
   Answer: A prepared value (a temporary folder, a fake) that pytest creates and passes in by parameter name.

3. **What does `--strict-markers` do?**
   Answer: It turns a marker that is not declared in the configuration into an error.

4. **What does coverage measure?**
   Answer: Which lines and branches of the code ran while the tests ran.

5. **Why does this repository inject a clock instead of sleeping?**
   Answer: So tests are fast and give the same answer every time.

## Further reading

- pytest 9.1: https://docs.pytest.org/en/stable/
- pytest-cov 7.1: https://pytest-cov.readthedocs.io/en/latest/
- coverage.py 7.17: https://coverage.readthedocs.io/en/7.17.0/
