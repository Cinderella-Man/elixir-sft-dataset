# Ticket: `AssertHelpers` — custom ExUnit assertion macros

Deliver a single-file Elixir module `AssertHelpers` exposing three custom ExUnit assertion macros for `use` inside test modules.

**Module-level requirements**

- Module name: `AssertHelpers`.
- `use AssertHelpers` must make all three macros available in the using module — i.e. the module defines a `__using__/1` macro that imports them.
- All three must be macros, not plain functions, so ExUnit reports the correct file and line number on failure.
- Every failure is surfaced with `ExUnit.Assertions.flunk/1`.
- Single file, no external dependencies beyond `ExUnit` and `Ecto` (the latter for the changeset macro).
- Deliverable: the complete module in a single file.

---

## `assert_changeset_error(changeset, field, message)`

Asserts the given Ecto changeset has at least one error on `field` whose message matches `message` by **exact string equality** — no substring, no regex, no interpolation of Ecto's `opts`.

**Input handling**

- Read errors from the `changeset`'s `errors` key directly — the standard Ecto shape: a keyword list of `{field, {message, opts}}` entries.
- Must **not** go through `Ecto.Changeset.traverse_errors/2` or otherwise require a real `%Ecto.Changeset{}` struct. Any struct or plain map exposing an `errors` key in that shape (e.g. a lightweight test double) must work identically.

**Matching**

- A field may appear more than once in the list. The assertion passes if **any** message recorded for `field` equals `message` exactly; duplicates and additional unrelated errors are irrelevant.

**Pass**

- Does not raise; produces no output.

**Failure**

- `flunk/1` with a message beginning with `assert_changeset_error failed`, always restating the inspected `field` and the inspected expected `message`. Then:
  - If `field` has **no** errors at all (including when the changeset has no errors whatsoever): the detail says the field has no errors and additionally shows *all* errors present on the changeset, grouped by field name → list of messages (an empty map when there are none).
  - If `field` has errors but none match: the detail shows the inspected list of messages actually present on that field, plus the expected message.

---

## `assert_recent(datetime, tolerance_seconds \\ 5)`

Asserts a `DateTime` (or `NaiveDateTime`) is within `tolerance_seconds` seconds of the current wall-clock time (`DateTime.utc_now()`). Default tolerance is **5** seconds.

**Type handling**

- A `%NaiveDateTime{}` is interpreted as being in `Etc/UTC`.
- A `%DateTime{}` is used as-is; any zone/offset it carries is respected when computing the difference.
- Any other value — `nil`, a `Date`, a string, an integer, etc. — is not a type error to be raised. It fails the assertion via `flunk/1` with a message of the form `assert_recent expected a DateTime or NaiveDateTime, got: <inspected value>`.

**Comparison**

- The difference is the **absolute** whole-second difference between now and the datetime, so a future datetime is treated symmetrically with a past one.
- **Inclusive**: a difference exactly equal to `tolerance_seconds` passes; only a strictly larger difference fails. A `tolerance_seconds` of `0` therefore requires the same whole second.

**Pass**

- Does not raise; produces no output.

**Failure**

- `flunk/1` with a message beginning with `assert_recent failed`, containing on separate labelled lines: the actual datetime as ISO-8601, the current UTC time as ISO-8601, the computed difference in seconds, and the literal word `tolerance` with the allowed value in seconds (e.g. `tolerance: 5s`).
- Also states by how many seconds the datetime lies outside the allowed window (difference minus tolerance).

---

## `assert_eventually(func, timeout_ms \\ 1000, interval_ms \\ 50)`

Repeatedly calls the zero-arity function `func` until it returns a "ready" value or `timeout_ms` elapses. Defaults: `timeout_ms = 1_000`, `interval_ms = 50`.

**Invocation**

- `func` is invoked **immediately**, before any sleeping. An already-satisfied condition succeeds without waiting, even when `timeout_ms` is `0`.

**Readiness rule** (a refinement of truthiness)

- Not ready yet, keep polling: `nil`, `false`, and **any bare atom other than `true`** (status atoms such as `:still_pending`, `:ok`, `:error`).
- Success: any other value — `true` itself, or a non-atom truthy value such as `42`, `"done"`, `{:ok, x}`, `[1]`. Ordinary predicates returning booleans are unaffected.

**Polling and deadline**

- While not ready, sleep `interval_ms` between calls.
- The deadline is measured against a monotonic clock starting when the macro begins, and is checked **after** each call, so `func` is always evaluated at least once and a call already in flight is never discarded.

**Success**

- Evaluates to `:ok`; does not raise.

**Timeout**

- `flunk/1` with a message beginning with `assert_eventually timed out`, reporting on separate labelled lines three numeric values: the configured `timeout_ms`, the elapsed time in milliseconds, and the configured `interval_ms`.
- Each of those three lines must be labelled with, respectively, the literal word `timeout`, the literal word `elapsed`, and the literal word `interval`; on each line the label word must appear **before** its number with no digit characters in between.
- The value is rendered with an `ms` unit suffix **immediately** after the number, no space — e.g. a line reading `timeout` … `1000ms`, another `elapsed` … `0ms`, another `interval` … `50ms`.
- The message also includes the **last value returned by `func`** rendered with `inspect/1` — so a function stuck on `:still_pending` yields a message containing `still_pending`, and one stuck on `false` contains `false`.
- The elapsed value is a non-negative millisecond count; it may be `0`.
