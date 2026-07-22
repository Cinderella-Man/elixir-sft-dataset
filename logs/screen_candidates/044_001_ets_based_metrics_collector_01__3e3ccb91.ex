defmodule Metrics do
  @moduledoc """
  Fast, concurrent-safe application metrics backed by an ETS table.

  `Metrics` supports two kinds of metrics that coexist in a single ETS table:

    * **counters** — monotonically increasing values bumped via `increment/2`,
      updated atomically with `:ets.update_counter/3`;
    * **gauges** — arbitrary values set via `gauge/2`, each call overwriting the
      previous value.

  A metric's type is never declared upfront. `increment/2` creates or bumps a
  counter entry and `gauge/2` creates or overwrites a gauge entry.

  The backing `GenServer` exists only to initialise and own the ETS table. The
  table is created as `:public` and `:named_table`, so the hot path
  (`increment/2`, `gauge/2`, and the read functions) operates directly on ETS
  and never serialises through a `GenServer.call/2`.
  """

  use GenServer

  @table __MODULE__

  ## Public API

  @doc """
  Starts the backing `GenServer` that owns the ETS table.

  Accepts a `:name` option for process registration, defaulting to `#{__MODULE__}`.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Atomically increments the counter `name` by `amount` (default `1`).

  Counters are monotonically increasing; `amount` should be non-negative. The
  increment happens directly against ETS via `:ets.update_counter/4` and does
  not serialise through the owning process. Returns `:ok`.
  """
  @spec increment(term(), integer()) :: :ok
  def increment(name, amount \\ 1) do
    _new = :ets.update_counter(@table, name, amount, {name, 0})
    :ok
  end

  @doc """
  Sets the gauge `name` to the exact `value`, overwriting any previous value.
  """
  @spec gauge(term(), number()) :: :ok
  def gauge(name, value) do
    true = :ets.insert(@table, {name, value})
    :ok
  end

  @doc """
  Returns the current value of the metric `name`, or `nil` if it does not exist.
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
  """
  @spec all() :: %{optional(term()) => number()}
  def all do
    @table
    |> :ets.tab2list()
    |> Map.new()
  end

  @doc """
  Resets the metric `name` back to `0`, regardless of counter or gauge type.
  """
  @spec reset(term()) :: :ok
  def reset(name) do
    true = :ets.insert(@table, {name, 0})
    :ok
  end

  @doc """
  Returns a point-in-time map of all current metrics.

  Identical in shape to `all/0`; the returned map is an immutable snapshot of
  the metrics at the moment of the call.
  """
  @spec snapshot() :: %{optional(term()) => number()}
  def snapshot do
    all()
  end

  ## GenServer callbacks

  @impl GenServer
  def init(_opts) do
    table =
      :ets.new(@table, [
        :set,
        :public,
        :named_table,
        read_concurrency: true,
        write_concurrency: true
      ])

    {:ok, %{table: table}}
  end
end