# Migrate existing code to a new spec

Starting point: the working, tested solution below, from a related task.
Change it — no ground-up rewrite — until it satisfies the specification
that follows. On any disagreement between the two (module name, public API,
behavior, constraints, output format), the new specification wins. Output
the complete updated code.

## Existing code (your starting point)

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

## New specification

Write me an Elixir module called `Metrics` that collects **latency/size distributions** using ETS for fast, concurrent-safe storage. This is a histogram collector (Prometheus-style), not a scalar counter/gauge collector.

I need these functions in the public API:

- `Metrics.start_link(opts \\ [])` to start the backing GenServer. It should accept a `:name` option for process registration (defaulting to `__MODULE__`) and a `:buckets` option: a sorted ascending list of integer upper bounds. Default to `[10, 50, 100, 500, 1000]`.
- `Metrics.observe(name, value)` to record a single integer observation (e.g. a request latency in ms) for the histogram `name`, returning `:ok`. `value` must be a non-negative integer. This is the hot path and MUST NOT serialize through the GenServer — it must go directly to ETS using `:ets.update_counter`. Recording an observation atomically bumps the total count, the running sum, and the count for the matching bucket. A value `v` falls into the bucket of the smallest boundary `b` such that `v <= b`; a value larger than every boundary falls into the implicit `+Inf` bucket.
- `Metrics.get(name)` to return the current summary of the histogram as a map `%{count: c, sum: s, average: avg, buckets: %{...}}`, or `nil` if nothing has ever been observed for `name`. The `:buckets` map is **cumulative** ("less-than-or-equal"): each configured boundary maps to the number of observations `<= that boundary`, plus an `:infinity` key mapping to the total count. `:average` is `sum / count` as a float (the average of an empty histogram never arises because `get` returns `nil` when there are no observations).
- `Metrics.all()` to return a map of `%{name => total_count}` across every histogram.
- `Metrics.reset(name)` to erase all recorded data for `name` so that a subsequent `get(name)` returns `nil`.

The ETS table must be public and named so `observe` can bypass the owning process for maximum throughput. The GenServer exists only to own the table and to hold the bucket configuration. Use only OTP/stdlib — no external dependencies. Give me the complete implementation in a single file.
