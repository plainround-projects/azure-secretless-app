# JSON

*The format of the app's answers and of its log lines. Pinned here: JSON (RFC 8259).*

## What it is

JSON is a text format for structured data. It has objects (`{"key": value}`), arrays (`[1, 2]`), strings, numbers, `true`, `false` and `null`. Almost every programming language and web service can read and write it.

## Why this repository uses it

Every answer of the app is JSON, and every log line is one JSON object, so Log Analytics can read the fields.

## Where it appears

| File | What it does with it |
|---|---|
| `src/secretless_app/interfaces/http.py` | `jsonify` builds the answers. |
| `src/secretless_app/infrastructure/logging.py` | Writes one JSON object per log line. |
| `tests/unit/infrastructure/test_logging_and_wiring.py` | Checks a log line parses back. |

## How it works underneath

A JSON document is a tree. An object maps names to values; an array is an ordered list. A reader parses the text into the language's own maps and lists, and a writer does the reverse. JSON has no comments and no trailing commas, and all keys are strings.

Programs that log JSON print one object per line, so a log system can read each line as a record. Azure Policy definitions are JSON documents: the rule is a nested tree of conditions.

## Walkthrough of this repository's use

```python
class JsonFormatter(logging.Formatter):
    """Render a record as JSON; fields passed through `extra=` become top-level keys."""

    def format(self, record: logging.LogRecord) -> str:
        """Return the JSON line for `record`."""
        payload: dict[str, Any] = {
            "ts": datetime.fromtimestamp(record.created, UTC).isoformat(timespec="milliseconds"),
            "level": record.levelname,
            "logger": record.name,
            "msg": record.getMessage(),
        }
        payload.update({key: value for key, value in vars(record).items() if key not in _RESERVED})
        if record.exc_info:
            payload["exc"] = self.formatException(record.exc_info)
        return json.dumps(payload, default=str)
```

A `logging.Formatter` turns a log record into text. This one builds a dictionary with the time (`ts`, UTC, to the millisecond), the level, the logger name and the message, adds the record's extra fields, adds the exception text if there is one, and returns `json.dumps(payload, default=str)`. `default=str` turns anything JSON cannot represent (a path, say) into text instead of failing. The output is one line, so a log system can read each line as a record.

```python
        return jsonify({"error": "upstream_access_denied", "service": error.service, "code": error.code}), 502
```

The error answers are JSON too, with a fixed `error` name a client can test for.

## Try it yourself

Print one structured log line.

```bash
BACKEND=memory .venv/bin/python -c "import logging; from secretless_app.infrastructure.logging import configure_logging; configure_logging('INFO'); logging.getLogger('demo').error('access denied by %s', 'blob', extra={'code': 'AuthorizationPermissionMismatch'})"
```

You should see something like this:

```text
{"ts": "2026-10-27T11:30:36.514+00:00", "level": "ERROR", "logger": "demo", "msg": "access denied by blob", "code": "AuthorizationPermissionMismatch"}
```

Run the log format tests.

```bash
.venv/bin/python -m pytest tests/unit/infrastructure/test_logging_and_wiring.py -q -p no:cacheprovider
```

You should see something like this:

```text
.....                                                                    [100%]
5 passed in 1.98s
```

## Mistakes people make

- Trailing commas and comments, which JSON does not allow.
- Using single quotes. Strings use double quotes.
- Putting a large number in JSON and losing precision in a reader that uses floating point.
- Parsing untrusted JSON into code. Only data is read here; nothing is executed.
- Forgetting that key order is not meaningful.

## Check yourself

1. **What are JSON's two container types?**
   Answer: Objects (names to values) and arrays (ordered lists).

2. **Can JSON have comments?**
   Answer: No.

3. **Why do loggers print one JSON object per line?**
   Answer: So a log system can treat each line as one record.

4. **What quote marks does JSON use?**
   Answer: Double quotes only.

5. **What is the value `null`?**
   Answer: The explicit absence of a value.

## Further reading

- JSON: https://www.json.org/json-en.html
- RFC 8259: https://www.rfc-editor.org/rfc/rfc8259
