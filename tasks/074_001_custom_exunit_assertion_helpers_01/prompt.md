Write me an Elixir module called `AssertHelpers` that provides three custom ExUnit assertion macros intended to be `use`d inside test modules.

`use AssertHelpers` must make all three macros available in the using module (i.e. the module defines a `__using__/1` macro that imports them). All three must be macros (not plain functions) so that ExUnit reports the correct file and line number on failure. Every failure is surfaced with `ExUnit.Assertions.flunk/1`. The module should be a single file with no external dependencies beyond `ExUnit` and `Ecto` (for the changeset macro).

I need these macros:

## `assert_changeset_error(changeset, field, message)`

Asserts that the given Ecto changeset has at least one error on `field` whose message matches `message` by **exact string equality** (no substring, no regex, no interpolation of Ecto's `opts`).

Behavior contract:

- The macro reads the errors from the `changeset`'s `errors` key directly — the standard Ecto shape: a keyword list of `{field, {message, opts}}` entries. It must **not** go through `Ecto.Changeset.traverse_errors/2` or otherwise require a real `%Ecto.Changeset{}` struct: any struct or plain map that exposes an `errors` key in that shape (e.g. a lightweight test double) must work identically.
- A field may appear more than once in the list. The assertion passes if **any** of the messages recorded for `field` equals `message` exactly; duplicates and additional unrelated errors are irrelevant.
- Passing case: the macro does not raise and produces no output.
- Failure case: `flunk/1` with a message that begins with `assert_changeset_error failed` and always restates the inspected `field` and the inspected expected `message`. Then:
  - If `field` has **no** errors at all (including when the changeset has no errors whatsoever), the detail says that the field has no errors and additionally shows *all* errors present on the changeset, grouped by field name → list of messages (an empty map when there are none).
  - If `field` has errors but none match, the detail shows the inspected list of messages actually present on that field, plus the expected message.

## `assert_recent(datetime, tolerance_seconds \\ 5)`

Asserts that a `DateTime` (or `NaiveDateTime`) is within `tolerance_seconds` seconds of the current wall-clock time (`DateTime.utc_now()`). Default tolerance is **5** seconds.

Behavior contract:

- A `%NaiveDateTime{}` is interpreted as being in `Etc/UTC`; a `%DateTime{}` is used as-is (any zone/offset it carries is respected when computing the difference).
- Any other value — `nil`, a `Date`, a string, an integer, etc. — is not a type error to be raised: it fails the assertion via `flunk/1` with a message of the form `assert_recent expected a DateTime or NaiveDateTime, got: <inspected value>`.
- The difference is the **absolute** whole-second difference between now and the datetime, so a datetime in the future is treated symmetrically with one in the past.
- The comparison is **inclusive**: a difference exactly equal to `tolerance_seconds` passes; only a strictly larger difference fails. A `tolerance_seconds` of `0` therefore requires the same whole second.
- Passing case: the macro does not raise and produces no output.
- Failure case: `flunk/1` with a message that begins with `assert_recent failed` and contains, on separate labelled lines: the actual datetime as ISO-8601, the current UTC time as ISO-8601, the computed difference in seconds, and the literal word `tolerance` with the allowed value in seconds (e.g. `tolerance: 5s`). It also states by how many seconds the datetime lies outside the allowed window (difference minus tolerance).

## `assert_eventually(func, timeout_ms \\ 1000, interval_ms \\ 50)`

Repeatedly calls the zero-arity function `func` until it returns a "ready" value or `timeout_ms` elapses. Defaults: `timeout_ms = 1_000`, `interval_ms = 50`.

Behavior contract:

- `func` is invoked **immediately**, before any sleeping. A condition that is already satisfied succeeds without waiting, even when `timeout_ms` is `0`.
- "Ready" is a refinement of truthiness: `nil`, `false`, and **any bare atom other than `true`** (status atoms such as `:still_pending`, `:ok`, `:error`) count as "not ready yet" and keep polling. Any other value — `true` itself, or a non-atom truthy value such as `42`, `"done"`, `{:ok, x}`, `[1]` — counts as success. (Ordinary predicates returning booleans are unaffected.)
- While not ready, the macro sleeps `interval_ms` between calls. The deadline is measured against a monotonic clock starting when the macro begins; the deadline is checked **after** each call, so `func` is always evaluated at least once and a call already in flight is never discarded.
- On success the macro evaluates to `:ok` and does not raise.
- On timeout: `flunk/1` with a message that begins with `assert_eventually timed out` and reports, on separate labelled lines, the configured `timeout_ms`, the elapsed time in milliseconds, the configured `interval_ms` — each of these three rendered with an `ms` unit suffix immediately after the number (e.g. `1000ms`) — and the **last value returned by `func`** rendered with `inspect/1` (so a function stuck on `:still_pending` yields a message containing `still_pending`, and one stuck on `false` contains `false`). The elapsed value is a non-negative millisecond count.

Give me the complete module in a single file.
