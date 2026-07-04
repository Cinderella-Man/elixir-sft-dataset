# Fill in the middle: implement the blanked test

Below is a module and its ExUnit test harness with the body of ONE `test` removed
(marked `# TODO`). The test's name states what it must verify. Implement just that one
test so the harness passes for a correct implementation of the module.

## Module under test

```elixir
defmodule Metrics do
  @moduledoc """
  A concurrent-safe histogram collector backed by a named public ETS table.

  Each observation atomically bumps three ETS counters — the total count, the
  running sum, and the matching bucket — all via `:ets.update_counter/4`, so
  the hot path never serialises through the owning GenServer. The GenServer
  exists only to own the table and hold the bucket configuration.

  ## Quick start

      {:ok, _pid} = Metrics.start_link()
      Metrics.observe(:latency_ms, 42)      # => :ok
      Metrics.get(:latency_ms)
      # => %{count: 1, sum: 42, average: 42.0,
      #      buckets: %{10 => 0, 50 => 1, 100 => 1, 500 => 1, 1000 => 1, infinity: 1}}
  """

  use GenServer

  @table __MODULE__
  @default_buckets [10, 50, 100, 500, 1000]

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  @doc """
  Starts the backing GenServer and creates the ETS table.

  ## Options

    * `:name` — registration name for the process. Defaults to `#{__MODULE__}`.
    * `:buckets` — sorted ascending list of integer upper bounds.
      Defaults to `#{inspect(@default_buckets)}`.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    {name, init_opts} = Keyword.pop(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, init_opts, name: name)
  end

  @doc """
  Records a single non-negative integer observation for histogram `name`.

  Atomically increments the total count, the running sum and the count for the
  bucket that `value` falls into. Returns `:ok`.
  """
  @spec observe(term(), non_neg_integer()) :: :ok
  def observe(name, value) when is_integer(value) and value >= 0 do
    :ets.update_counter(@table, {name, :count}, {2, 1}, {{name, :count}, 0})
    :ets.update_counter(@table, {name, :sum}, {2, value}, {{name, :sum}, 0})
    u = bucket_for(value)
    :ets.update_counter(@table, {name, :bucket, u}, {2, 1}, {{name, :bucket, u}, 0})
    :ok
  end

  @doc """
  Returns the histogram summary for `name`, or `nil` if nothing was observed.

  The `:buckets` map is cumulative: each configured boundary maps to the number
  of observations `<=` that boundary, plus an `:infinity` key for the total.
  """
  @spec get(term()) :: map() | nil
  def get(name) do
    case :ets.lookup(@table, {name, :count}) do
      [] ->
        nil

      [{_, count}] ->
        sum = counter({name, :sum})
        boundaries = :persistent_term.get({@table, :buckets})

        {cumulative, _running} =
          Enum.reduce(boundaries, {%{}, 0}, fn b, {acc, running} ->
            running = running + counter({name, :bucket, b})
            {Map.put(acc, b, running), running}
          end)

        buckets = Map.put(cumulative, :infinity, count)
        %{count: count, sum: sum, average: sum / count, buckets: buckets}
    end
  end

  @doc """
  Returns a map of `%{name => total_count}` across every histogram.
  """
  @spec all() :: %{term() => non_neg_integer()}
  def all do
    :ets.foldl(
      fn
        {{name, :count}, v}, acc -> Map.put(acc, name, v)
        _other, acc -> acc
      end,
      %{},
      @table
    )
  end

  @doc """
  Erases all recorded data for `name`, so a later `get/1` returns `nil`.
  """
  @spec reset(term()) :: :ok
  def reset(name) do
    :ets.match_delete(@table, {{name, :count}, :_})
    :ets.match_delete(@table, {{name, :sum}, :_})
    :ets.match_delete(@table, {{name, :bucket, :_}, :_})
    :ok
  end

  # ---------------------------------------------------------------------------
  # Internal helpers
  # ---------------------------------------------------------------------------

  defp bucket_for(value) do
    boundaries = :persistent_term.get({@table, :buckets})
    Enum.find(boundaries, :inf, fn b -> value <= b end)
  end

  defp counter(key) do
    case :ets.lookup(@table, key) do
      [{^key, v}] -> v
      [] -> 0
    end
  end

  # ---------------------------------------------------------------------------
  # GenServer callbacks
  # ---------------------------------------------------------------------------

  @impl GenServer
  def init(opts) do
    buckets = Keyword.get(opts, :buckets, @default_buckets)
    :persistent_term.put({@table, :buckets}, buckets)

    :ets.new(@table, [
      :set,
      :named_table,
      :public,
      read_concurrency: true,
      write_concurrency: true
    ])

    {:ok, %{buckets: buckets}}
  end
end
```

## Test harness — implement the `# TODO` test

```elixir
defmodule MetricsTest do
  use ExUnit.Case, async: false

  setup do
    start_supervised!(Metrics)
    :ok
  end

  # -------------------------------------------------------
  # observe / get basics
  # -------------------------------------------------------

  test "get returns nil for a histogram that has never been observed" do
    assert Metrics.get(:never) == nil
  end

  test "a single observation produces count 1 and matching sum" do
    assert :ok = Metrics.observe(:lat, 42)
    summary = Metrics.get(:lat)
    assert summary.count == 1
    assert summary.sum == 42
    assert_in_delta summary.average, 42.0, 0.0001
  end

  test "count, sum and average accumulate across observations" do
    # TODO
  end

  # -------------------------------------------------------
  # cumulative buckets
  # -------------------------------------------------------

  test "buckets are cumulative (less-than-or-equal)" do
    Metrics.observe(:lat, 5)
    Metrics.observe(:lat, 42)
    Metrics.observe(:lat, 42)
    b = Metrics.get(:lat).buckets
    assert b[10] == 1
    assert b[50] == 3
    assert b[100] == 3
    assert b[500] == 3
    assert b[1000] == 3
    assert b[:infinity] == 3
  end

  test "values above every boundary land only in the +Inf bucket" do
    Metrics.observe(:big, 5000)
    b = Metrics.get(:big).buckets
    assert b[10] == 0
    assert b[1000] == 0
    assert b[:infinity] == 1
    assert Metrics.get(:big).sum == 5000
  end

  test "a value exactly on a boundary is included at that boundary" do
    Metrics.observe(:edge, 50)
    b = Metrics.get(:edge).buckets
    assert b[10] == 0
    assert b[50] == 1
    assert b[100] == 1
  end

  # -------------------------------------------------------
  # custom buckets
  # -------------------------------------------------------

  test "custom bucket boundaries are honoured" do
    stop_supervised(Metrics)
    start_supervised!({Metrics, buckets: [1, 2, 3]})
    Metrics.observe(:x, 2)
    b = Metrics.get(:x).buckets
    assert b[1] == 0
    assert b[2] == 1
    assert b[3] == 1
    assert b[:infinity] == 1
  end

  # -------------------------------------------------------
  # all / reset
  # -------------------------------------------------------

  test "all returns a map of name => total count" do
    Metrics.observe(:a, 1)
    Metrics.observe(:a, 2)
    Metrics.observe(:b, 900)
    result = Metrics.all()
    assert result[:a] == 2
    assert result[:b] == 1
  end

  test "reset erases a histogram entirely" do
    Metrics.observe(:gone, 10)
    assert Metrics.get(:gone).count == 1
    Metrics.reset(:gone)
    assert Metrics.get(:gone) == nil
    assert Metrics.all()[:gone] == nil
  end

  test "reset of one histogram leaves others intact" do
    Metrics.observe(:keep, 3)
    Metrics.observe(:drop, 3)
    Metrics.reset(:drop)
    assert Metrics.get(:drop) == nil
    assert Metrics.get(:keep).count == 1
  end

  # -------------------------------------------------------
  # concurrency
  # -------------------------------------------------------

  test "100 concurrent observations aggregate correctly" do
    1..100
    |> Enum.map(fn _ -> Task.async(fn -> Metrics.observe(:c, 7) end) end)
    |> Task.await_many(5_000)

    summary = Metrics.get(:c)
    assert summary.count == 100
    assert summary.sum == 700
    assert summary.buckets[10] == 100
  end
end
```
