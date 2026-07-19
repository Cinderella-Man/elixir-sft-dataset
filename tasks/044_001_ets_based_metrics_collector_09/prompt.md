# Implement the missing function

Below is the complete specification of a task, followed by a working,
fully tested module that solves it — except that `init` has been
removed: every clause body is blanked to `# TODO`. Implement exactly that
function so the whole module passes the task's full test suite again.
Change nothing else — every other function, attribute, and clause must
stay exactly as shown.

## The task

Write me an Elixir module called `Metrics` that collects application metrics using ETS tables for fast, concurrent-safe storage.

I need these functions in the public API:
- `Metrics.start_link(opts \\ [])` to start the backing GenServer. It should accept a `:name` option for process registration, defaulting to `__MODULE__`.
- `Metrics.increment(name, amount \\ 1)` to atomically increment a named counter by `amount`. Counters are monotonically increasing and should never decrease. Use `:ets.update_counter` for atomicity. An `amount` of `0` is valid: it leaves an existing counter unchanged, and it creates a missing counter at `0`.
- `Metrics.gauge(name, value)` to set a named gauge to an exact value. Gauges can go up or down freely — each call overwrites the previous value. Returns `:ok` on create and on overwrite.
- `Metrics.get(name)` to return the current value of a metric by name, or `nil` if it doesn't exist.
- `Metrics.all()` to return all metrics as a map of `%{name => value}`.
- `Metrics.reset(name)` to set a metric back to `0` regardless of whether it is a counter or gauge. Returns `:ok` — including for a name that does not exist yet, which is created at `0`.
- `Metrics.snapshot()` to return a point-in-time map of all current metrics, identical in shape to `all/0` but semantically communicating immutability of the returned data.

Counters and gauges can coexist in the same table — there is no need to declare a metric's type upfront; `increment` creates or bumps a counter entry and `gauge` creates or overwrites a gauge entry. The ETS table should be public and named so that `increment` can bypass the GenServer process for maximum throughput (i.e., the hot path for incrementing must not serialize through a GenServer `call`). The GenServer is only needed for initialisation and owning the table.

Give me the complete implementation in a single file. Use only OTP/stdlib — no external dependencies.

## Additional interface contract

- `Metrics.increment/2` returns `:ok`, not the counter's new value.

## The module with `init` missing

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

  def init(_opts) do
    # TODO
  end
end
```

Give me only the complete implementation of `init` (including any
`@doc`/`@spec`/`@impl` lines that belong directly above it) — the
function alone, not the whole module.
