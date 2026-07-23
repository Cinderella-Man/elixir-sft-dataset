# One bug. Find it. Fix it.

The module below implements the task that follows, except for a single
behavior bug. The bottom of this prompt shows the real failure report from
its (hidden) test suite. Deliver the full corrected module: smallest
possible change, no restructuring, nothing else touched.

## Target behavior

# `Metrics` — ETS-Backed Application Metrics Collector

## Overview

This document specifies an Elixir module named `Metrics` that collects application metrics using ETS tables for fast, concurrent-safe storage. The deliverable is the complete implementation in a single file, built on OTP/stdlib only, with no external dependencies.

Counters and gauges coexist in the same table. A metric's type need not be declared upfront: `increment` creates or bumps a counter entry, and `gauge` creates or overwrites a gauge entry.

## Storage and process architecture

The ETS table must be public and registered under the exact name `Metrics` (the module name). It must be created with `read_concurrency: true` and `write_concurrency: true`. Callers may verify all of this via `:ets.info/2`.

This arrangement exists so that `increment` can bypass the GenServer process for maximum throughput — that is, the hot path for incrementing must not serialize through a GenServer `call`. The GenServer is needed only for initialisation and for owning the table.

## API

The public API consists of the following functions.

- `Metrics.start_link(opts \\ [])` — starts the backing GenServer. It accepts a `:name` option for process registration, defaulting to `__MODULE__`.
- `Metrics.increment(name, amount \\ 1)` — atomically increments a named counter by `amount`. Atomicity is achieved with `:ets.update_counter`. Counters are monotonically increasing and never decrease.
- `Metrics.gauge(name, value)` — sets a named gauge to an exact value. Gauges may go up or down freely; each call overwrites the previous value. It returns `:ok` both on create and on overwrite.
- `Metrics.get(name)` — returns the current value of a metric by name, or `nil` if that metric does not exist.
- `Metrics.all()` — returns all metrics as a map of `%{name => value}`.
- `Metrics.reset(name)` — sets a metric back to `0`, regardless of whether it is a counter or a gauge. It returns `:ok`.
- `Metrics.snapshot()` — returns a point-in-time map of all current metrics, identical in shape to `all/0`, but semantically communicating immutability of the returned data.

## Additional interface contract

`Metrics.increment/2` returns `:ok`, not the counter's new value.

## Edge cases

- A negative `amount` passed to `Metrics.increment/2` is out of contract. The function head must be guarded so that such a call raises `FunctionClauseError` and stores nothing.
- An `amount` of `0` is valid: it leaves an existing counter unchanged, and it creates a missing counter at `0`.
- `Metrics.reset(name)` returns `:ok` even for a name that does not exist yet; that name is created at `0`.
- `Metrics.get(name)` yields `nil` for a name that has never been recorded.

## The buggy module

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
    :ets.update_counter(@table, name, {3, amount}, {name, 0})
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

## Failing test report

```
18 of 30 test(s) failed:

  * test increment creates a counter starting at 1
      errors were found at the given arguments:
      
        * 3rd argument: the position in the update operation is out of range
      

  * test increment adds the given amount
      errors were found at the given arguments:
      
        * 3rd argument: the position in the update operation is out of range
      

  * test increment defaults amount to 1
      errors were found at the given arguments:
      
        * 3rd argument: the position in the update operation is out of range
      

  * test counters are monotonically increasing — reset brings back to 0
      errors were found at the given arguments:
      
        * 3rd argument: the position in the update operation is out of range
      

  (…14 more)
```
