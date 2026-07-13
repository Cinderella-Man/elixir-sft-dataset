# Write tests for this module

Below is a completed Elixir module and the original specification it was built to
satisfy. Write a comprehensive ExUnit test harness that verifies a correct
implementation of this module.

Requirements for the harness:
- Define a module `<Module>Test` that does `use ExUnit.Case, async: false`.
- Do NOT call `ExUnit.start()` — the evaluator starts ExUnit itself.
- Make it self-contained: any fakes, clock Agents, or helpers are defined inline.
- Cover the full public API and the important edge cases described in the spec.
- It must compile with ZERO warnings (prefix unused variables with `_`; match float
  zero as `+0.0`/`-0.0`).
- Give me the complete harness in a single file.

## Original specification

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
- On timeout: `flunk/1` with a message that begins with `assert_eventually timed out` and reports, on separate labelled lines, the configured `timeout_ms`, the elapsed time in milliseconds, the configured `interval_ms`, and the **last value returned by `func`** rendered with `inspect/1` (so a function stuck on `:still_pending` yields a message containing `still_pending`, and one stuck on `false` contains `false`). The elapsed value is a non-negative millisecond count.

Give me the complete module in a single file.

## Module under test

```elixir
defmodule AssertHelpers do
  @moduledoc """
  Custom ExUnit assertion macros for common testing patterns.

  ## Usage

      defmodule MyApp.SomeTest do
        use ExUnit.Case
        use AssertHelpers

        test "example" do
          assert_changeset_error(changeset, :email, "is invalid")
          assert_recent(inserted_at)
          assert_eventually(fn -> some_async_condition() end)
        end
      end
  """

  @doc false
  defmacro __using__(_opts) do
    quote do
      import AssertHelpers
    end
  end

  # ---------------------------------------------------------------------------
  # assert_changeset_error/3
  # ---------------------------------------------------------------------------

  @doc """
  Asserts that `changeset` has at least one error on `field` whose message
  matches `message` exactly.

  On failure the error output shows either the actual messages present on the
  field or a note that the field carries no errors at all, so the cause is
  immediately obvious.

  ## Example

      assert_changeset_error(changeset, :email, "has already been taken")
  """
  defmacro assert_changeset_error(changeset, field, message) do
    quote bind_quoted: [changeset: changeset, field: field, message: message] do
      # Read errors directly from the struct/map rather than going through
      # Ecto.Changeset.traverse_errors/2, which guards on %Ecto.Changeset{} and
      # would crash on lightweight test fakes that share the same {:field,
      # {message, opts}} keyword-list shape.
      field_errors =
        changeset.errors
        |> Keyword.get_values(field)
        |> Enum.map(fn {msg, _opts} -> msg end)

      all_errors =
        Enum.group_by(changeset.errors, fn {k, _} -> k end, fn {_, {msg, _}} -> msg end)

      unless message in field_errors do
        failure_detail =
          if field_errors == [] do
            "  field #{inspect(field)} has no errors\n" <>
              "  (all errors: #{inspect(all_errors)})"
          else
            "  field #{inspect(field)} has errors: #{inspect(field_errors)}\n" <>
              "  expected to find: #{inspect(message)}"
          end

        ExUnit.Assertions.flunk("""
        assert_changeset_error failed

          changeset field: #{inspect(field)}
          expected message: #{inspect(message)}
        #{failure_detail}
        """)
      end
    end
  end

  # ---------------------------------------------------------------------------
  # assert_recent/2
  # ---------------------------------------------------------------------------

  @doc """
  Asserts that `datetime` (a `DateTime` or `NaiveDateTime`) is within
  `tolerance_seconds` of the current wall-clock time (`DateTime.utc_now()`).

  Defaults to a 5-second tolerance.

  On failure the output shows the actual datetime, the current time, and the
  computed absolute difference in seconds.

  ## Examples

      assert_recent(record.inserted_at)
      assert_recent(record.inserted_at, 30)
  """
  defmacro assert_recent(datetime, tolerance_seconds \\ 5) do
    quote bind_quoted: [datetime: datetime, tolerance_seconds: tolerance_seconds] do
      now = DateTime.utc_now()

      # Normalise both sides to DateTime so diff/3 always works.
      dt_utc =
        case datetime do
          %DateTime{} = dt ->
            dt

          %NaiveDateTime{} = ndt ->
            DateTime.from_naive!(ndt, "Etc/UTC")

          other ->
            ExUnit.Assertions.flunk(
              "assert_recent expected a DateTime or NaiveDateTime, got: #{inspect(other)}"
            )
        end

      diff_seconds = DateTime.diff(now, dt_utc, :second) |> abs()

      unless diff_seconds <= tolerance_seconds do
        ExUnit.Assertions.flunk("""
        assert_recent failed

          actual datetime : #{DateTime.to_iso8601(dt_utc)}
          current UTC time: #{DateTime.to_iso8601(now)}
          difference      : #{diff_seconds}s
          tolerance       : #{tolerance_seconds}s

        The datetime is #{diff_seconds - tolerance_seconds}s outside the allowed window.
        """)
      end
    end
  end

  # ---------------------------------------------------------------------------
  # assert_eventually/3
  # ---------------------------------------------------------------------------

  @doc """
  Repeatedly calls the zero-arity function `func` every `interval_ms`
  milliseconds until it returns a truthy value or `timeout_ms` elapses.

  If the timeout is reached the assertion fails, reporting the total time
  waited and the last value returned by `func`.

  Defaults: `timeout_ms = 1_000`, `interval_ms = 50`.

  ## Examples

      assert_eventually(fn -> Process.whereis(:my_server) != nil end)
      assert_eventually(fn -> Agent.get(:counter, & &1) >= 5 end, 2_000, 100)
  """
  defmacro assert_eventually(func, timeout_ms \\ 1_000, interval_ms \\ 50) do
    quote bind_quoted: [func: func, timeout_ms: timeout_ms, interval_ms: interval_ms] do
      deadline = System.monotonic_time(:millisecond) + timeout_ms

      result =
        AssertHelpers.__poll__(func, deadline, interval_ms, _last_value = nil)

      case result do
        {:ok, _value} ->
          :ok

        {:error, last_value, elapsed_ms} ->
          ExUnit.Assertions.flunk("""
          assert_eventually timed out

            timeout   : #{timeout_ms}ms
            elapsed   : #{elapsed_ms}ms
            interval  : #{interval_ms}ms
            last value: #{inspect(last_value)}

          The condition did not become truthy within the allowed window.
          """)
      end
    end
  end

  # Public only so the macro-generated `quote` block can call it from any
  # module. Not intended for direct use.
  @doc false
  @spec __poll__((-> term()), integer(), non_neg_integer(), term()) ::
          {:ok, term()} | {:error, term(), integer()}
  def __poll__(func, deadline, interval_ms, _last_value) do
    value = func.()
    now = System.monotonic_time(:millisecond)

    cond do
      # Success when the value is truthy AND is not a bare atom (other than
      # `true` itself).  This lets integer/tuple/list returns like `42` count
      # as "done" while keeping status atoms such as `:still_pending` or `:ok`
      # in the "not yet" bucket.  All real polling predicates (comparisons,
      # `!= nil`, etc.) already return a proper boolean so they are unaffected.
      value != nil and value != false and (not is_atom(value) or value == true) ->
        {:ok, value}

      now >= deadline ->
        elapsed = interval_ms + (now - (deadline - interval_ms))
        {:error, value, max(elapsed, 0)}

      true ->
        Process.sleep(interval_ms)
        __poll__(func, deadline, interval_ms, value)
    end
  end
end
```
