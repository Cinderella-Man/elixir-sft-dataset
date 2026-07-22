# Task

Implement the `assert_eventually/3` macro in the `AssertHelpers` module below.

`assert_eventually(func, timeout_ms \\ 1_000, interval_ms \\ 50)` is a custom ExUnit
assertion macro. It repeatedly calls the zero-arity function `func` every `interval_ms`
milliseconds until `func` returns a "ready" value, or until `timeout_ms` milliseconds have
elapsed.

What it must do:

- Because it is a macro, it must `quote` its body. Use `bind_quoted:` for `func`,
  `timeout_ms`, and `interval_ms` so each is evaluated exactly once at the call site and
  ExUnit reports the correct file/line on failure.
- Compute a deadline from the current monotonic clock:
  `System.monotonic_time(:millisecond) + timeout_ms`.
- Delegate the actual polling loop to the already-provided helper
  `AssertHelpers.__poll__/4`, passing `func`, the deadline, `interval_ms`, and an initial
  last value of `nil`. (The helper is public only so macro-expanded code in other modules
  can call it; do not reimplement the loop inline.)
- `__poll__/4` returns either `{:ok, value}` on success or `{:error, last_value, elapsed_ms}`
  on timeout. Note the "ready" semantics it implements: `nil`, `false`, and any bare atom
  other than `true` (status atoms such as `:still_pending` or `:ok`) mean "not ready yet"
  and keep polling; `true` itself or any other non-atom truthy value (e.g. `42`) counts as
  success.
- On `{:ok, _value}` the assertion simply passes — return `:ok` and do not raise.
- On `{:error, last_value, elapsed_ms}` fail the assertion via `ExUnit.Assertions.flunk/1`
  with a multi-line message that includes the configured `timeout_ms`, the total time
  waited (`elapsed_ms`), the `interval_ms`, and the last value returned by `func` rendered
  with `inspect/1` (so a function stuck on `:still_pending` produces a message containing
  `still_pending`).

Implement one function at a time; only the body of `assert_eventually/3` is missing.

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
    # TODO
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