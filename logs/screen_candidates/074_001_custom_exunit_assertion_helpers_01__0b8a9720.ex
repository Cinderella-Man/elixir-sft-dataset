defmodule AssertHelpers do
  @moduledoc """
  Custom ExUnit assertion macros for changesets, timestamps and eventual conditions.

  Use it inside a test module to import all three macros:

      defmodule MyTest do
        use ExUnit.Case, async: true
        use AssertHelpers

        test "it works" do
          assert_changeset_error(changeset, :name, "can't be blank")
          assert_recent(record.inserted_at)
          assert_eventually(fn -> Agent.get(pid, & &1.done) end)
        end
      end

  All three helpers are macros so that ExUnit reports the failing file and line of the
  call site, and every failure is surfaced through `ExUnit.Assertions.flunk/1`.
  """

  @doc """
  Imports `assert_changeset_error/3`, `assert_recent/1,2` and `assert_eventually/1,2,3`
  into the using module.
  """
  @spec __using__(Macro.t()) :: Macro.t()
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
  Asserts that `changeset` has at least one error on `field` whose message is exactly
  equal to `message`.

  The errors are read straight from the changeset's `errors` key, which is expected to be
  a keyword list of `{field, {message, opts}}` entries — the standard Ecto shape. Any
  struct or map exposing that key works, including lightweight test doubles; no
  `Ecto.Changeset.traverse_errors/2` call and no message interpolation is performed.

      assert_changeset_error(changeset, :email, "has invalid format")
  """
  @spec assert_changeset_error(Macro.t(), Macro.t(), Macro.t()) :: Macro.t()
  defmacro assert_changeset_error(changeset, field, message) do
    quote do
      AssertHelpers.__changeset_error__(
        unquote(changeset),
        unquote(field),
        unquote(message)
      )
    end
  end

  @doc """
  Asserts that `datetime` is within `tolerance_seconds` seconds of `DateTime.utc_now/0`.

  A `NaiveDateTime` is interpreted as UTC, a `DateTime` is used as-is. The comparison uses
  the absolute whole-second difference and is inclusive of the tolerance. Any other value
  fails the assertion rather than raising. Default tolerance is 5 seconds.

      assert_recent(user.inserted_at)
      assert_recent(user.inserted_at, 30)
  """
  @spec assert_recent(Macro.t(), Macro.t()) :: Macro.t()
  defmacro assert_recent(datetime, tolerance_seconds \\ 5) do
    quote do
      AssertHelpers.__recent__(unquote(datetime), unquote(tolerance_seconds))
    end
  end

  @doc """
  Repeatedly calls the zero-arity `func` until it returns a ready value or `timeout_ms`
  elapses, sleeping `interval_ms` between attempts.

  `func` is called immediately, before any sleeping. `nil`, `false` and any bare atom other
  than `true` (for example `:still_pending`) count as "not ready yet"; every other value is
  a success. Evaluates to `:ok` on success and flunks on timeout, reporting the last value
  returned by `func`.

      assert_eventually(fn -> Repo.get(Job, id).state == "done" end)
      assert_eventually(fn -> :ets.lookup(:cache, :key) != [] end, 5_000, 100)
  """
  @spec assert_eventually(Macro.t(), Macro.t(), Macro.t()) :: Macro.t()
  defmacro assert_eventually(func, timeout_ms \\ 1_000, interval_ms \\ 50) do
    quote do
      AssertHelpers.__eventually__(
        unquote(func),
        unquote(timeout_ms),
        unquote(interval_ms)
      )
    end
  end

  # -- Runtime implementations (private API, called from the macros above) --------------

  @doc false
  @spec __changeset_error__(map(), atom(), String.t()) :: :ok
  def __changeset_error__(changeset, field, message) do
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
        but the field has no errors
        all errors on the changeset: #{inspect(all_errors(errors))}\
        """)

      true ->
        ExUnit.Assertions.flunk("""
        assert_changeset_error failed
        field: #{inspect(field)}
        expected message: #{inspect(message)}
        actual messages on field: #{inspect(messages)}\
        """)
    end
  end

  @doc false
  @spec __recent__(term(), integer()) :: :ok
  def __recent__(%NaiveDateTime{} = naive, tolerance_seconds) do
    naive
    |> DateTime.from_naive!("Etc/UTC")
    |> __recent__(tolerance_seconds)
  end

  def __recent__(%DateTime{} = datetime, tolerance_seconds) do
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

  def __recent__(other, _tolerance_seconds) do
    ExUnit.Assertions.flunk(
      "assert_recent expected a DateTime or NaiveDateTime, got: #{inspect(other)}"
    )
  end

  @doc false
  @spec __eventually__((-> term()), non_neg_integer(), non_neg_integer()) :: :ok
  def __eventually__(func, timeout_ms, interval_ms) when is_function(func, 0) do
    started_at = System.monotonic_time(:millisecond)
    poll(func, started_at, timeout_ms, interval_ms)
  end

  # -- Helpers ---------------------------------------------------------------------------

  defp poll(func, started_at, timeout_ms, interval_ms) do
    value = func.()

    cond do
      ready?(value) ->
        :ok

      elapsed(started_at) >= timeout_ms ->
        timed_out(value, started_at, timeout_ms, interval_ms)

      true ->
        Process.sleep(interval_ms)
        poll(func, started_at, timeout_ms, interval_ms)
    end
  end

  defp timed_out(value, started_at, timeout_ms, interval_ms) do
    ExUnit.Assertions.flunk("""
    assert_eventually timed out
    timeout: #{timeout_ms}ms
    elapsed: #{elapsed(started_at)}ms
    interval: #{interval_ms}ms
    last value: #{inspect(value)}\
    """)
  end

  defp elapsed(started_at) do
    max(System.monotonic_time(:millisecond) - started_at, 0)
  end

  # "Ready" is a refinement of truthiness: bare status atoms other than `true` keep polling.
  defp ready?(true), do: true
  defp ready?(value) when is_atom(value), do: false
  defp ready?(_value), do: true

  defp messages_for(errors, field) do
    for {^field, error} <- errors, do: error_message(error)
  end

  defp all_errors(errors) do
    Enum.reduce(errors, %{}, fn {field, error}, acc ->
      Map.update(acc, field, [error_message(error)], &(&1 ++ [error_message(error)]))
    end)
  end

  defp error_message({message, _opts}), do: message
  defp error_message(message), do: message
end