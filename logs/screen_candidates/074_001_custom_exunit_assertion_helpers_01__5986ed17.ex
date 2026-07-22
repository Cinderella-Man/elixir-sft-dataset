defmodule AssertHelpers do
  @moduledoc """
  Custom ExUnit assertion macros for common testing needs.

  `use AssertHelpers` inside a test module (or test case template) to import
  three assertion macros:

    * `assert_changeset_error/3` — assert an `Ecto.Changeset` has a specific
      error message on a field.
    * `assert_recent/2` — assert a `DateTime`/`NaiveDateTime` is close to now.
    * `assert_eventually/3` — poll a function until it returns a truthy value.

  All three are implemented as macros so that ExUnit reports the failing
  file and line at the call site rather than inside this module.
  """

  @doc """
  Imports the assertion macros into the calling module.
  """
  @spec __using__(term()) :: Macro.t()
  defmacro __using__(_opts) do
    quote do
      import AssertHelpers
    end
  end

  @doc """
  Asserts that `changeset` has at least one error on `field` whose message is
  exactly equal to `message`.

  On failure, the raised message lists the actual error messages present on the
  field, or notes that the field has no errors at all.
  """
  @spec assert_changeset_error(Macro.t(), Macro.t(), Macro.t()) :: Macro.t()
  defmacro assert_changeset_error(changeset, field, message) do
    quote do
      cs_changeset = unquote(changeset)
      cs_field = unquote(field)
      cs_expected = unquote(message)

      cs_messages =
        cs_changeset.errors
        |> Keyword.get_values(cs_field)
        |> Enum.map(fn {cs_msg, _opts} -> cs_msg end)

      if cs_expected in cs_messages do
        true
      else
        cs_detail =
          case cs_messages do
            [] -> "field #{inspect(cs_field)} has no errors"
            _ -> "errors on #{inspect(cs_field)}: #{inspect(cs_messages)}"
          end

        ExUnit.Assertions.flunk(
          "Expected error #{inspect(cs_expected)} on field " <>
            "#{inspect(cs_field)}, but #{cs_detail}"
        )
      end
    end
  end

  @doc """
  Asserts that `datetime` (a `DateTime` or `NaiveDateTime`) is within
  `tolerance_seconds` seconds of the current UTC wall-clock time.

  On failure, the raised message shows the actual datetime, the current time,
  the allowed `tolerance` in seconds, and the computed difference in seconds.
  """
  @spec assert_recent(Macro.t(), Macro.t()) :: Macro.t()
  defmacro assert_recent(datetime, tolerance_seconds \\ 5) do
    quote do
      recent_dt = unquote(datetime)
      recent_tol = unquote(tolerance_seconds)
      recent_now = DateTime.utc_now()

      recent_diff =
        case recent_dt do
          %NaiveDateTime{} ->
            NaiveDateTime.diff(DateTime.to_naive(recent_now), recent_dt, :second)

          _ ->
            DateTime.diff(recent_now, recent_dt, :second)
        end

      if abs(recent_diff) <= recent_tol do
        recent_dt
      else
        ExUnit.Assertions.flunk(
          "Expected #{inspect(recent_dt)} to be recent " <>
            "(tolerance: #{recent_tol}s); now is #{inspect(recent_now)}, " <>
            "difference is #{recent_diff} seconds"
        )
      end
    end
  end

  @doc """
  Asserts that the zero-arity function `func` eventually returns a truthy value.

  `func` is invoked immediately and then every `interval_ms` milliseconds until
  it returns a truthy value or `timeout_ms` milliseconds have elapsed. On
  timeout, the raised message includes the total time waited and the last value
  returned by `func`.
  """
  @spec assert_eventually(Macro.t(), Macro.t(), Macro.t()) :: Macro.t()
  defmacro assert_eventually(func, timeout_ms \\ 1000, interval_ms \\ 50) do
    quote do
      ev_timeout = unquote(timeout_ms)
      ev_interval = unquote(interval_ms)

      {ev_value, ev_elapsed} =
        AssertHelpers.eventually_poll(unquote(func), ev_timeout, ev_interval)

      if ev_value do
        ev_value
      else
        ExUnit.Assertions.flunk(
          "Expected condition to become truthy within " <>
            "#{ev_timeout}ms, but it timed out after " <>
            "#{ev_elapsed}ms; last value: #{inspect(ev_value)}"
        )
      end
    end
  end

  @doc """
  Polls `func` until it returns a truthy value or `timeout_ms` elapses.

  Returns `{value, elapsed_ms}` where `value` is the final value returned by
  `func` (truthy on success, falsy on timeout) and `elapsed_ms` is the total
  number of milliseconds spent polling. Intended to be called from the
  `assert_eventually/3` macro expansion.
  """
  @spec eventually_poll((-> term()), non_neg_integer(), non_neg_integer()) ::
          {term(), non_neg_integer()}
  def eventually_poll(func, timeout_ms, interval_ms)
      when is_function(func, 0) and is_integer(timeout_ms) and is_integer(interval_ms) do
    start = System.monotonic_time(:millisecond)
    do_poll(func, start + timeout_ms, interval_ms, start)
  end

  @spec do_poll((-> term()), integer(), non_neg_integer(), integer()) ::
          {term(), non_neg_integer()}
  defp do_poll(func, deadline, interval, start) do
    value = func.()

    if value do
      {value, System.monotonic_time(:millisecond) - start}
    else
      now = System.monotonic_time(:millisecond)

      if now >= deadline do
        {value, now - start}
      else
        Process.sleep(min(interval, deadline - now))
        do_poll(func, deadline, interval, start)
      end
    end
  end
end