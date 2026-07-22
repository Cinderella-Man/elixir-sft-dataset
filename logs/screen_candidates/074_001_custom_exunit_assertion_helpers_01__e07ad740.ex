defmodule AssertHelpers do
  @moduledoc """
  Custom ExUnit assertion macros for common testing needs.

  `use AssertHelpers` inside a test module to import the following macros:

    * `assert_changeset_error/3` — assert an Ecto changeset has a specific error
      message on a given field.
    * `assert_recent/2` — assert a `DateTime`/`NaiveDateTime` is close to now.
    * `assert_eventually/3` — poll a zero-arity function until it becomes truthy.

  Every assertion is implemented as a macro so that, on failure, ExUnit reports
  the file and line number of the call site rather than of this module.

  The only dependencies are `ExUnit` (for `ExUnit.Assertions.flunk/1`) and `Ecto`
  (whose `Ecto.Changeset` struct backs `assert_changeset_error/3`).
  """

  @doc """
  Imports the `AssertHelpers` assertion macros into the calling module.
  """
  @spec __using__(Keyword.t()) :: Macro.t()
  defmacro __using__(_opts) do
    quote do
      import AssertHelpers
    end
  end

  @doc """
  Asserts that `changeset` has at least one error on `field` whose message is
  exactly equal to `message`.

  On failure, the surfaced message lists the actual errors present on `field`,
  or notes that the field carries no errors at all.
  """
  @spec assert_changeset_error(Macro.t(), Macro.t(), Macro.t()) :: Macro.t()
  defmacro assert_changeset_error(changeset, field, message) do
    quote do
      changeset = unquote(changeset)
      field = unquote(field)
      expected = unquote(message)

      errors =
        for {msg, _opts} <- Keyword.get_values(changeset.errors, field), do: msg

      cond do
        errors == [] ->
          ExUnit.Assertions.flunk(
            "Expected error #{inspect(expected)} on field #{inspect(field)}, " <>
              "but that field has no errors at all"
          )

        expected in errors ->
          :ok

        true ->
          ExUnit.Assertions.flunk(
            "Expected error #{inspect(expected)} on field #{inspect(field)}, " <>
              "but the actual errors are: #{inspect(errors)}"
          )
      end
    end
  end

  @doc """
  Asserts that `datetime` (a `DateTime` or `NaiveDateTime`) is within
  `tolerance_seconds` seconds of `DateTime.utc_now/0`.

  On failure, the message reports the actual datetime, the current time, the
  configured tolerance, and the computed difference expressed in seconds.
  """
  @spec assert_recent(Macro.t(), Macro.t()) :: Macro.t()
  defmacro assert_recent(datetime, tolerance_seconds \\ 5) do
    quote do
      datetime = unquote(datetime)
      tolerance = unquote(tolerance_seconds)
      now = DateTime.utc_now()

      diff =
        case datetime do
          %DateTime{} ->
            DateTime.diff(now, datetime, :second)

          %NaiveDateTime{} ->
            NaiveDateTime.diff(DateTime.to_naive(now), datetime, :second)
        end

      if abs(diff) <= tolerance do
        :ok
      else
        ExUnit.Assertions.flunk(
          "Expected #{inspect(datetime)} to be recent (tolerance: #{tolerance}s), " <>
            "but now is #{inspect(now)} and the difference is #{diff} seconds"
        )
      end
    end
  end

  @doc """
  Repeatedly calls the zero-arity function `func` every `interval_ms`
  milliseconds until it returns a truthy value or `timeout_ms` elapses.

  "Ready" means `func` returned `true` itself or a non-atom truthy value (such
  as `42`). `nil`, `false`, and any bare status atom (e.g. `:still_pending`,
  `:ok`) are treated as "not ready yet" and cause further polling.

  On timeout, the failure message includes the total time waited and the last
  value returned by `func`, rendered with `inspect/1`.
  """
  @spec assert_eventually(Macro.t(), Macro.t(), Macro.t()) :: Macro.t()
  defmacro assert_eventually(func, timeout_ms \\ 1000, interval_ms \\ 50) do
    quote do
      func = unquote(func)
      interval = unquote(interval_ms)
      start = System.monotonic_time(:millisecond)
      deadline = start + unquote(timeout_ms)

      ready? = fn value ->
        case value do
          nil -> false
          false -> false
          true -> true
          atom when is_atom(atom) -> false
          _other -> true
        end
      end

      poll = fn poll ->
        value = func.()

        cond do
          ready?.(value) ->
            {:ok, value}

          System.monotonic_time(:millisecond) >= deadline ->
            {:timeout, value}

          true ->
            Process.sleep(interval)
            poll.(poll)
        end
      end

      case poll.(poll) do
        {:ok, _value} ->
          :ok

        {:timeout, last_value} ->
          waited = System.monotonic_time(:millisecond) - start

          ExUnit.Assertions.flunk(
            "assert_eventually timed out after #{waited}ms; " <>
              "last value returned by func: #{inspect(last_value)}"
          )
      end
    end
  end
end