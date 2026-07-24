# Fill in the middle: implement the blanked test

Below is a module and its ExUnit test harness with the body of ONE `test` removed
(marked `# TODO`). The test's name states what it must verify. Implement just that one
test so the harness passes for a correct implementation of the module.

## Module under test

```elixir
defmodule Metrics do
  @moduledoc """
  A concurrent-safe metrics collector backed by a named public ETS table.

  Counters and gauges share the same table. The GenServer exists solely to
  initialise and own the table — all hot-path reads and counter increments
  go directly to ETS and never serialise through the process.

  ## Backing table

  The table is named `Metrics` (the module itself), is a `:set`, and is
  created with `:named_table`, `:public`, `read_concurrency: true` and
  `write_concurrency: true`. Those properties are part of the contract: the
  table must be reachable by name from any process, writable without the
  owner's involvement, and tuned for simultaneous readers and writers.

  ## Quick start

      {:ok, _pid} = Metrics.start_link()

      Metrics.increment(:http_requests)          # => :ok
      Metrics.increment(:http_requests, 4)        # => :ok
      Metrics.gauge(:memory_mb, 412)             # => :ok
      Metrics.get(:http_requests)                # => 5
      Metrics.get(:does_not_exist)               # => nil
      Metrics.all()                              # => %{http_requests: 5, memory_mb: 412}
      Metrics.snapshot()                         # => %{http_requests: 5, memory_mb: 412}
      Metrics.reset(:http_requests)              # => :ok
      Metrics.get(:http_requests)                # => 0
  """

  use GenServer

  # The ETS table name is fixed and module-scoped.  Because the table is
  # :public and :named_table every caller can hit it directly without
  # routing through the owning process.
  @table __MODULE__

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  @doc """
  Starts the backing GenServer and creates the ETS table.

  ## Options

    * `:name` — registration name for the GenServer process.
      Defaults to `#{__MODULE__}`.

  Returns `{:ok, pid}` on success, or `{:error, {:already_started, pid}}`
  if the server is already running.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    {name, init_opts} = Keyword.pop(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, init_opts, name: name)
  end

  @doc """
  Atomically increments the counter `name` by `amount` (default `1`).

  If the counter does not yet exist it is initialised to `0` before the
  increment is applied (a first call therefore stores `amount`). The
  increment is performed with `:ets.update_counter/4`, which is atomic and
  requires no round-trip to the GenServer.

  `amount` must be a non-negative integer — counters are monotonically
  increasing and never decrease. An `amount` of `0` is explicitly allowed:
  it leaves an existing counter untouched and creates a missing one at `0`.

  Returns `:ok`.
  """
  @spec increment(term(), non_neg_integer()) :: :ok
  def increment(name, amount \\ 1) when is_integer(amount) and amount >= 0 do
    :ets.update_counter(@table, name, {2, amount}, {name, 0})
    :ok
  end

  @doc """
  Sets the gauge `name` to exactly `value`, overwriting any previous entry.

  Gauges are free to move up or down. Each `:ets.insert` is itself atomic,
  but unlike `increment/2`'s atomic read-modify-write a gauge set is a plain
  overwrite: concurrent sets to the same key are not coordinated (last-write
  wins), which is acceptable for gauge semantics.

  Returns `:ok`.
  """
  @spec gauge(term(), number()) :: :ok
  def gauge(name, value) do
    :ets.insert(@table, {name, value})
    :ok
  end

  @doc """
  Returns the current value of `name`, or `nil` if it has never been set.
  """
  @spec get(term()) :: number() | nil
  def get(name) do
    case :ets.lookup(@table, name) do
      [{^name, value}] -> value
      [] -> nil
    end
  end

  @doc """
  Returns all metrics as a map of `%{name => value}`.

  The map is built from a full ETS table scan (a point-in-time capture);
  `snapshot/0` is an alias whose name makes that intent explicit.
  """
  @spec all() :: %{term() => number()}
  def all do
    :ets.tab2list(@table)
    |> Map.new()
  end

  @doc """
  Returns a point-in-time snapshot of all metrics as `%{name => value}`.

  Semantically identical to `all/0` but signals to the reader that the
  returned map is an immutable capture — subsequent mutations do not
  affect it.
  """
  @spec snapshot() :: %{term() => number()}
  def snapshot, do: all()

  @doc """
  Resets the metric `name` to `0`.

  Works for both counters and gauges. If `name` does not exist it is
  created with the value `0`.

  Returns `:ok`.
  """
  @spec reset(term()) :: :ok
  def reset(name) do
    :ets.insert(@table, {name, 0})
    :ok
  end

  # ---------------------------------------------------------------------------
  # GenServer callbacks
  # ---------------------------------------------------------------------------

  @impl GenServer
  def init(_opts) do
    # :set          — one entry per key (duplicate keys overwrite)
    # :named_table  — accessible by name from any process
    # :public       — any process may read and write without going through the owner
    # read_concurrency / write_concurrency — kernel-level optimisations for
    #   the mixed read-heavy / write-heavy workloads typical of metrics
    :ets.new(@table, [
      :set,
      :named_table,
      :public,
      read_concurrency: true,
      write_concurrency: true
    ])

    {:ok, %{}}
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
  # Counters
  # -------------------------------------------------------

  test "increment creates a counter starting at 1" do
    assert :ok = Metrics.increment(:hits)
    assert Metrics.get(:hits) == 1
  end

  test "increment adds the given amount" do
    Metrics.increment(:hits, 5)
    Metrics.increment(:hits, 3)
    assert Metrics.get(:hits) == 8
  end

  test "increment defaults amount to 1" do
    Metrics.increment(:clicks)
    Metrics.increment(:clicks)
    Metrics.increment(:clicks)
    assert Metrics.get(:hits) == nil
    assert Metrics.get(:clicks) == 3
  end

  test "counters are monotonically increasing — reset brings back to 0" do
    Metrics.increment(:score, 10)
    assert Metrics.get(:score) == 10
    Metrics.reset(:score)
    assert Metrics.get(:score) == 0
    Metrics.increment(:score, 3)
    assert Metrics.get(:score) == 3
  end

  test "increment accepts an amount of 0 and leaves an existing counter unchanged" do
    Metrics.increment(:zero_bump, 7)
    assert :ok = Metrics.increment(:zero_bump, 0)
    assert Metrics.get(:zero_bump) == 7
    assert :ok = Metrics.increment(:zero_bump, 0)
    assert Metrics.get(:zero_bump) == 7
  end

  test "increment with an amount of 0 creates a missing counter at 0" do
    assert Metrics.get(:fresh_zero) == nil
    assert :ok = Metrics.increment(:fresh_zero, 0)
    assert Metrics.get(:fresh_zero) == 0
    assert Metrics.all()[:fresh_zero] == 0
  end

  test "increment/2 returns :ok rather than the counter's new value" do
    assert Metrics.increment(:ret_val) == :ok
    assert Metrics.increment(:ret_val, 4) == :ok
    assert Metrics.increment(:ret_val, 0) == :ok
    assert Metrics.get(:ret_val) == 5
  end

  # -------------------------------------------------------
  # Gauges
  # -------------------------------------------------------

  test "gauge sets an exact value" do
    Metrics.gauge(:temp, 72)
    assert Metrics.get(:temp) == 72
  end

  test "gauge overwrites on repeated calls" do
    Metrics.gauge(:temp, 72)
    Metrics.gauge(:temp, 55)
    Metrics.gauge(:temp, 100)
    assert Metrics.get(:temp) == 100
  end

  test "gauge can decrease" do
    Metrics.gauge(:queue_depth, 50)
    Metrics.gauge(:queue_depth, 10)
    assert Metrics.get(:queue_depth) == 10
  end

  test "gauge can be set to 0" do
    Metrics.gauge(:active, 7)
    Metrics.gauge(:active, 0)
    assert Metrics.get(:active) == 0
  end

  test "gauge/2 returns :ok on create and on overwrite" do
    assert Metrics.gauge(:ret_gauge, 1) == :ok
    assert Metrics.gauge(:ret_gauge, 2) == :ok
    assert :ok = Metrics.gauge(:ret_gauge, -5)
    assert Metrics.get(:ret_gauge) == -5
  end

  # -------------------------------------------------------
  # get/1
  # -------------------------------------------------------

  test "get returns nil for unknown metric" do
    assert Metrics.get(:does_not_exist) == nil
  end

  # -------------------------------------------------------
  # reset/1
  # -------------------------------------------------------

  test "reset sets a gauge back to 0" do
    Metrics.gauge(:level, 99)
    Metrics.reset(:level)
    assert Metrics.get(:level) == 0
  end

  test "reset on unknown metric sets it to 0" do
    Metrics.reset(:brand_new)
    assert Metrics.get(:brand_new) == 0
  end

  test "reset/1 returns :ok for counters, gauges and unknown metrics" do
    Metrics.increment(:ret_counter, 3)
    Metrics.gauge(:ret_g, 9)

    assert Metrics.reset(:ret_counter) == :ok
    assert Metrics.reset(:ret_g) == :ok
    assert Metrics.reset(:never_seen_before) == :ok
    assert :ok = Metrics.reset(:ret_counter)

    assert Metrics.get(:ret_counter) == 0
    assert Metrics.get(:ret_g) == 0
    assert Metrics.get(:never_seen_before) == 0
  end

  # -------------------------------------------------------
  # all/0 and snapshot/0
  # -------------------------------------------------------

  test "all/0 returns a map of all metrics" do
    Metrics.increment(:a, 1)
    Metrics.gauge(:b, 42)
    result = Metrics.all()
    assert is_map(result)
    assert result[:a] == 1
    assert result[:b] == 42
  end

  test "snapshot/0 returns the same data as all/0" do
    Metrics.increment(:x, 7)
    Metrics.gauge(:y, 3)
    assert Metrics.snapshot() == Metrics.all()
  end

  test "snapshot is a point-in-time copy — mutating after doesn't change it" do
    Metrics.increment(:counter, 1)
    snap = Metrics.snapshot()
    Metrics.increment(:counter, 99)
    assert snap[:counter] == 1
    assert Metrics.get(:counter) == 100
  end

  # -------------------------------------------------------
  # Key independence
  # -------------------------------------------------------

  test "different metric names are completely independent" do
    Metrics.increment(:foo, 3)
    Metrics.gauge(:bar, 10)
    assert Metrics.get(:foo) == 3
    assert Metrics.get(:bar) == 10
  end

  # -------------------------------------------------------
  # Backing ETS table contract
  # -------------------------------------------------------

  test "the backing table is a public named set tuned for concurrent access" do
    assert :ets.info(Metrics, :type) == :set
    assert :ets.info(Metrics, :named_table) == true
    assert :ets.info(Metrics, :protection) == :public
    assert :ets.info(Metrics, :read_concurrency) == true
    assert :ets.info(Metrics, :write_concurrency) == true
  end

  # -------------------------------------------------------
  # Concurrent increments
  # -------------------------------------------------------

  test "100 concurrent tasks each incrementing by 1 produce a final value of 100" do
    # TODO
  end

  test "concurrent increments and gauge writes don't interfere with each other" do
    tasks =
      Enum.map(1..50, fn _ -> Task.async(fn -> Metrics.increment(:c1, 1) end) end) ++
        Enum.map(1..50, fn i -> Task.async(fn -> Metrics.gauge(:g1, i) end) end)

    Task.await_many(tasks, 5_000)

    assert Metrics.get(:c1) == 50
    assert Metrics.get(:g1) in 1..50
  end

  test "start_link registers the server under a custom :name option" do
    :ok = stop_supervised(Metrics)

    pid = start_supervised!({Metrics, name: :custom_metrics_server})

    assert Process.whereis(:custom_metrics_server) == pid
    assert :ok = Metrics.increment(:via_custom_name, 2)
    assert Metrics.get(:via_custom_name) == 2
  end

  test "increment and get still work while the owning GenServer is suspended" do
    :sys.suspend(Metrics)

    try do
      assert :ok = Metrics.increment(:hot_path, 3)
      assert :ok = Metrics.increment(:hot_path)
      assert Metrics.get(:hot_path) == 4
    after
      :sys.resume(Metrics)
    end
  end

  test "gauge and reset still work while the owning GenServer is suspended" do
    :sys.suspend(Metrics)

    try do
      assert :ok = Metrics.gauge(:hot_gauge, 12)
      assert Metrics.get(:hot_gauge) == 12
      assert :ok = Metrics.reset(:hot_gauge)
      assert Metrics.get(:hot_gauge) == 0
    after
      :sys.resume(Metrics)
    end
  end

  test "a negative increment amount never lowers an existing counter" do
    Metrics.increment(:downward, 10)

    try do
      Metrics.increment(:downward, -4)
    rescue
      _ -> :ok
    catch
      _, _ -> :ok
    end

    assert Metrics.get(:downward) >= 10
  end

  test "a negative increment amount raises rather than returning :ok" do
    Metrics.increment(:strict_down, 6)

    assert_raise FunctionClauseError, fn -> Metrics.increment(:strict_down, -1) end

    assert Metrics.get(:strict_down) == 6
  end

  test "start_link defaults the process registration name to the module itself" do
    assert is_pid(Process.whereis(Metrics))
  end

  test "all/0 and snapshot/0 return an empty map when nothing has been recorded" do
    assert Metrics.all() == %{}
    assert Metrics.snapshot() == %{}
  end
end
```
