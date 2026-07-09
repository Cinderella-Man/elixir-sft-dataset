Write me an Elixir module called `AssertHelpers` that provides three custom ExUnit assertion macros intended to be `use`d inside test modules.

I need these macros:

- `assert_changeset_error(changeset, field, message)` — asserts that the given Ecto changeset has at least one error on `field` whose message matches `message`. The match should be exact string equality. On failure, the error message should show the actual errors present on that field (or note that the field has no errors at all), so the developer immediately knows what went wrong.

- `assert_recent(datetime, tolerance_seconds \\ 5)` — asserts that a `DateTime` (or `NaiveDateTime`) is within `tolerance_seconds` seconds of the current wall-clock time (`DateTime.utc_now()`). On failure, show the actual datetime, the current time, and the computed difference so the developer can diagnose it instantly.

- `assert_eventually(func, timeout_ms \\ 1000, interval_ms \\ 50)` — repeatedly calls the zero-arity function `func` every `interval_ms` milliseconds until it returns a truthy value or `timeout_ms` elapses. If it times out, the assertion should fail with a message that includes the total time waited and the last value returned by `func`.

All three must be macros (not plain functions) so that ExUnit can report the correct file and line number on failure. Use `ExUnit.Assertions.flunk/1` for surfacing failure messages. The module should be a single file with no external dependencies beyond `ExUnit` and `Ecto` (for the changeset macro).

Give me the complete module in a single file.

## Additional interface contract

- The `assert_recent` failure message must contain the literal word "tolerance" and state the allowed tolerance value in seconds (e.g. `tolerance: 5s`). The computed difference must likewise be expressed in seconds — its numeric value and/or the word "second" must appear in the message alongside the actual datetime.
- `assert_eventually` refines "truthy": `nil`, `false`, and any bare atom other than `true` (status atoms such as `:still_pending` or `:ok`) count as "not ready yet" and keep polling; any other return — `true` itself or a non-atom truthy value such as `42` — counts as success. On timeout, the failure message must contain the last value returned by `func` rendered with `inspect/1` (a function stuck on `:still_pending` yields a message containing `still_pending`).