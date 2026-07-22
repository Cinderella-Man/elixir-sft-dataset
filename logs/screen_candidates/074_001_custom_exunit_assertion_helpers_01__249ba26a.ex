defmodule AssertHelpers do
  @moduledoc """
  Custom ExUnit assertion macros for changeset errors, recency of timestamps and
  eventual consistency.

  Use it inside a test module to import all three macros:

      defmodule MyTest do
        use ExUnit.Case
        use AssertHelpers

        test "it works" do
          assert_changeset_error(changeset, :name, "can't be blank")
          assert_recent(user.inserted_at)
          assert_eventually(fn -> Process.alive?(pid) == false end)
        end
      end

  All three are macros so that ExUnit reports the file and line of the calling
  test on failure, and every failure is surfaced through `ExUnit.Assertions.flunk/1`.
  """

  @doc """
  Imports `assert_changeset_error/3`, `assert_recent/1,2` and
  `assert_eventually/1,2,3` into the using module.
  """
  defmacro __using__(_opts) do
    quote do
      import AssertHelpers,
        only: [
          assert_changeset_error: 3,
          assert_recent: 1,
          assert_recent: 2,
          assert_eventually: 1,
          assert_eventually: 2,
          assert_eventually: 3
        ]
    end
  end

  @doc """
  Asserts that `changeset` has at least one error on `field` whose message is
  exactly equal to `message`.

  The errors are read straight from the changeset's `errors` key, which is expected
  to hold the standard Ecto shape — a keyword list of `{field, {message, opts}}`
  entries. Any struct or plain map exposing that key works, including lightweight
  test doubles; `Ecto.Changeset.traverse_errors/2` is never invoked, so `opts` are
  not interpolated and matching is plain string equality.

  ## Examples

      assert_changeset_error(changeset, :email, "has invalid format")
  """
  @spec assert_changeset_error(Macro.t(), Macro.t(), Macro.t()) :: Macro.t()
  defmacro assert_changeset_error(changeset, field, message) do
    quote do
      AssertHelpers.__assert_changeset_error__(
        unquote(changeset),
        unquote(field),
        unquote(message)
      )
    end
  end

  @doc """
  Asserts that `datetime` is within `tolerance_seconds` seconds of `DateTime.utc_now/0`.

  A `NaiveDateTime` is interpreted as UTC; a `DateTime` is used as-is. The comparison
  uses the absolute whole-second difference and is inclusive, so a difference exactly
  equal to the tolerance passes. Values that are neither a `DateTime` nor a
  `NaiveDateTime` fail the assertion instead of raising.

  ## Examples

      assert_recent(user.inserted_at)
      assert_recent(user.inserted_at, 60)
  """
  @spec assert_recent(Macro.t(), Macro.t()) :: Macro.t()
  defmacro assert_recent(datetime, tolerance_seconds \\ 5) do
    quote do
      AssertHelpers.__assert_recent__(unquote(datetime), unquote(tolerance_seconds))
    end
  end

  @doc """
  Repeatedly calls the zero-arity `func` until it returns a ready value or `timeout_ms`
  elapses, sleeping `interval_ms` between attempts.

  `func` is called immediately, before any sleeping, and the deadline is checked after
  each call, so it always runs at least once. A value is "ready" unless it is `nil`,
  `false`, or a bare atom other than `true` — status atoms such as `:still_pending`
  keep the loop polling. Evaluates to `:ok` on success.

  ## Examples

      assert_eventually(fn -> Repo.aggregate(Job, :count) == 1 end)
      assert_eventually(fn -> Cache.fetch(:key) end, 5_000, 100)
  """
  @spec assert_eventually(Macro.t(), Macro.t(), Macro.t()) :: Macro.t()
  defmacro assert_eventually(func, timeout_ms \\ 1_000, interval_ms \\ 50) do
    quote do
      AssertHelpers.__assert_eventually__(
        unquote(func),
        unquote(timeout_ms),
        unquote(interval_ms)
      )
    end
  end

  @doc false
  @spec __assert_changeset_error__(map(), atom(), String.t()) :: :ok
  def __assert_changeset_error__(changeset, field, message) do
    errors = Map.get(changeset, :errors) || []
    messages = messages_for(errors, field)

    cond do
      message in messages ->
        :ok

      messages == [] ->
        ExUnit.Assertions.flunk("""
        assert_changeset_error failed
        field: #{inspect(field)}
        expected message: #{inspect(message)}
        the field has no errors
        all errors on changeset: #{inspect(all_errors(errors))}\
        """)

      true ->
        ExUnit.Assertions.flunk("""
        assert_changeset_error failed
        field: #{inspect(field)}
        expected message: #{inspect(message)}
        messages present on field: #{inspect(messages)}\
        """)
    end
  end

  @doc false
  @spec __assert_recent__(term(), integer()) :: :ok
  def __assert_recent__(%DateTime{} = datetime, tolerance_seconds) do
    check_recent(datetime, tolerance_seconds)
  end

  def __assert_recent__(%NaiveDateTime{} = datetime, tolerance_seconds) do
    datetime
    |> DateTime.from_naive!("Etc/UTC")
    |> check_recent(tolerance_seconds)
  end

  def __assert_recent__(other, _tolerance_seconds) do
    ExUnit.Assertions.flunk(
      "assert_recent expected a DateTime or NaiveDateTime, got: #{inspect(other)}"
    )
  end

  @doc false
  @spec __assert_eventually__((-> term()), non_neg_integer(), non_neg_integer()) :: :ok
  def __assert_eventually__(func, timeout_ms, interval_ms) do
    started_at = System.monotonic_time(:millisecond)
    poll(func, timeout_ms, interval_ms, started_at)
  end

  defp poll(func, timeout_ms, interval_ms, started_at) do
    value = func.()

    cond do
      ready?(value) ->
        :ok

      elapsed_ms(started_at) >= timeout_ms ->
        flunk_eventually(timeout_ms, interval_ms, started_at, value)

      true ->
        Process.sleep(interval_ms)
        poll(func, timeout_ms, interval_ms, started_at)
    end
  end

  defp flunk_eventually(timeout_ms, interval_ms, started_at, value) do
    ExUnit.Assertions.flunk("""
    assert_eventually timed out
    timeout: #{timeout_ms}ms
    elapsed: #{elapsed_ms(started_at)}ms
    interval: #{interval_ms}ms
    last value: #{inspect(value)}\
    """)
  end

  defp elapsed_ms(started_at) do
    max(System.monotonic_time(:millisecond) - started_at, 0)
  end

  defp ready?(nil), do: false
  defp ready?(false), do: false
  defp ready?(true), do: true
  defp ready?(value) when is_atom(value), do: false
  defp ready?(_value), do: true

  defp check_recent(datetime, tolerance_seconds) do
    now = DateTime.utc_now()
    diff = abs(DateTime.diff(now, datetime, :second))

    if diff <= tolerance_seconds do
      :ok
    else
      ExUnit.Assertions.flunk("""
      assert_recent failed
      datetime: #{DateTime.to_iso8601(datetime)}
      now (UTC): #{DateTime.to_iso8601(now)}
      difference: #{diff}s
      tolerance: #{tolerance_seconds}s
      the datetime is #{diff - tolerance_seconds}s outside the allowed window\
      """)
    end
  end

  defp messages_for(errors, field) do
    for {error_field, error} <- errors, error_field == field, do: extract_message(error)
  end

  defp all_errors(errors) do
    Enum.reduce(errors, %{}, fn {field, error}, acc ->
      Map.update(acc, field, [extract_message(error)], &(&1 ++ [extract_message(error)]))
    end)
  end

  defp extract_message({message, _opts}), do: message
  defp extract_message(message), do: message
end