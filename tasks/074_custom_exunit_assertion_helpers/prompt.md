Write me an Elixir module called `AssertHelpers` that provides three custom ExUnit assertion macros intended to be `use`d inside test modules.

I need these macros:

- `assert_changeset_error(changeset, field, message)` — asserts that the given Ecto changeset has at least one error on `field` whose message matches `message`. The match should be exact string equality. On failure, the error message should show the actual errors present on that field (or note that the field has no errors at all), so the developer immediately knows what went wrong.

- `assert_recent(datetime, tolerance_seconds \\ 5)` — asserts that a `DateTime` (or `NaiveDateTime`) is within `tolerance_seconds` seconds of the current wall-clock time (`DateTime.utc_now()`). On failure, show the actual datetime, the current time, and the computed difference so the developer can diagnose it instantly.

- `assert_eventually(func, timeout_ms \\ 1000, interval_ms \\ 50)` — repeatedly calls the zero-arity function `func` every `interval_ms` milliseconds until it returns a truthy value or `timeout_ms` elapses. If it times out, the assertion should fail with a message that includes the total time waited and the last value returned by `func`.

All three must be macros (not plain functions) so that ExUnit can report the correct file and line number on failure. Use `ExUnit.Assertions.flunk/1` for surfacing failure messages. The module should be a single file with no external dependencies beyond `ExUnit` and `Ecto` (for the changeset macro).

Give me the complete module in a single file.