# Adapt existing code to a new specification

Below is a complete, working, tested Elixir solution to a related task. Do not
start from scratch: treat it as the codebase you have been asked to change.
Modify it to satisfy the new specification that follows — keep whatever carries
over, and change, add, or remove whatever the new specification requires.

Where the existing code and the new specification disagree (module name, public
API, behavior, constraints, output format), the new specification wins. Give me
the complete final result.

## Existing code (your starting point)

```elixir
defmodule Metrics do
  @moduledoc """
  A concurrent-safe metrics collector backed by a named public ETS table.

  Counters and gauges share the same table. The GenServer exists solely to
  own the table and survive crashes — all hot-path reads and counter
  increments go directly to ETS and never serialise through the process.

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
  increment is applied, so the first call returns `amount`. The increment
  is performed with `:ets.update_counter/4`, which is atomic and requires
  no round-trip to the GenServer.

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

  Gauges are free to move up or down. Unlike `increment/2` this write
  is not atomic with respect to concurrent gauge writes for the same key,
  which is acceptable for gauge semantics (last-write wins).

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

  The map is built from a full ETS table scan; prefer `snapshot/0` when
  the intent is to capture a point-in-time view.
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

Write me an Elixir module called `Metrics` that collects **time-windowed event rates** using ETS for fast, concurrent-safe storage. Instead of a single monotonic total, this collector buckets events by the wall-clock second at which they occur, so you can ask "how many events happened in the last N seconds?".

To keep the collector testable, time must be **injectable**: `start_link` accepts a `:clock` option — a zero-arity function returning the current Unix time in integer seconds — defaulting to `fn -> System.system_time(:second) end`.

I need these functions in the public API:

- `Metrics.start_link(opts \\ [])` to start the backing GenServer. It accepts `:name` (process registration, default `__MODULE__`) and `:clock` (as above).
- `Metrics.increment(name, amount \\ 1)` to record `amount` events for `name` at the current second, returning `:ok`. `amount` must be a non-negative integer, enforced by a guard clause: a negative or non-integer `amount` raises `FunctionClauseError`, while an `amount` of `0` is accepted and records nothing. This is the hot path and MUST NOT serialize through the GenServer — it must go directly to ETS via `:ets.update_counter`, bumping the per-second bucket for `name`.
- `Metrics.rate(name, window_seconds)` to return the total number of events recorded for `name` within the last `window_seconds` — i.e. all events whose bucket second is strictly greater than `now - window_seconds`, where `now` comes from the injected clock. Returns `0` for an unknown name.
- `Metrics.count(name)` to return the all-time total number of events recorded for `name` across every bucket, or `0` if nothing has been recorded for `name`.
- `Metrics.reset(name)` to delete every bucket for `name`.
- `Metrics.prune(retention_seconds)` to delete all buckets (across every name) whose second is `<= now - retention_seconds`, returning the number of buckets deleted (not the number of events removed). This lets the table be bounded over time.
- `Metrics.all()` to return a map of `%{name => all_time_total}`, containing only names that currently have buckets.

The ETS table must be public and named so `increment` can bypass the owning process. The GenServer exists only to own the table; the clock is stored so both the hot path and queries can read it. Use only OTP/stdlib — no external dependencies. Give me the complete implementation in a single file.
