# Write the missing @spec

Below is a complete, working module — except that the `@spec` for
`prune/1` has been removed; its place is marked `# TODO: @spec`.
Write exactly that typespec: one `@spec` attribute for `prune/1`,
consistent with the function's arguments, guards, and every return shape
the implementation can produce. Change nothing else.

## The module with the `@spec` for `prune/1` missing

```elixir
defmodule Metrics do
  @moduledoc """
  A concurrent-safe *time-windowed rate* collector backed by a named public
  ETS table.

  Events are bucketed by the wall-clock second at which they occur — the ETS
  key is `{name, second}` — so queries can answer "how many events in the last
  N seconds?". Recording is a lock-free `:ets.update_counter/4` on the public
  table and never routes through the owning GenServer.

  Time is injectable via the `:clock` option (a zero-arity function returning
  integer Unix seconds), which makes rates deterministic under test. The clock
  is stored in `:persistent_term` so both the hot path and queries can read it.

  ## Quick start

      {:ok, _pid} = Metrics.start_link()
      Metrics.increment(:requests)         # => :ok
      Metrics.rate(:requests, 60)          # events in the last 60s
      Metrics.count(:requests)             # all-time total
  """

  use GenServer

  @table __MODULE__

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  @doc """
  Starts the backing GenServer and creates the ETS table.

  ## Options

    * `:name` — registration name for the process. Defaults to `#{__MODULE__}`.
    * `:clock` — zero-arity function returning the current Unix time in integer
      seconds. Defaults to `fn -> System.system_time(:second) end`.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    {name, init_opts} = Keyword.pop(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, init_opts, name: name)
  end

  @doc """
  Records `amount` events (default 1) for `name` at the current second.

  Atomically bumps the per-second bucket via `:ets.update_counter/4`. Returns
  `:ok`.
  """
  @spec increment(term(), non_neg_integer()) :: :ok
  def increment(name, amount \\ 1) when is_integer(amount) and amount >= 0 do
    second = now()
    key = {name, second}
    :ets.update_counter(@table, key, {2, amount}, {key, 0})
    :ok
  end

  @doc """
  Returns the number of events recorded for `name` within the last
  `window_seconds` — every bucket whose second is `> now - window_seconds`.
  """
  @spec rate(term(), pos_integer()) :: number()
  def rate(name, window_seconds) do
    cutoff = now() - window_seconds

    @table
    |> :ets.select([{{{name, :"$1"}, :"$2"}, [{:>, :"$1", cutoff}], [:"$2"]}])
    |> Enum.sum()
  end

  @doc "Returns the all-time total number of events recorded for `name`."
  @spec count(term()) :: number()
  def count(name) do
    @table
    |> :ets.select([{{{name, :"$1"}, :"$2"}, [], [:"$2"]}])
    |> Enum.sum()
  end

  @doc "Deletes every bucket for `name`."
  @spec reset(term()) :: :ok
  def reset(name) do
    :ets.match_delete(@table, {{name, :_}, :_})
    :ok
  end

  @doc """
  Deletes all buckets (across every name) whose second is `<= now -
  retention_seconds`. Returns the number of buckets deleted.
  """
  # TODO: @spec
  def prune(retention_seconds) do
    cutoff = now() - retention_seconds
    :ets.select_delete(@table, [{{{:_, :"$1"}, :_}, [{:"=<", :"$1", cutoff}], [true]}])
  end

  @doc "Returns a map of `%{name => all_time_total}`."
  @spec all() :: %{term() => non_neg_integer()}
  def all do
    :ets.foldl(
      fn {{name, _second}, amount}, acc ->
        Map.update(acc, name, amount, &(&1 + amount))
      end,
      %{},
      @table
    )
  end

  # ---------------------------------------------------------------------------
  # Internal helpers
  # ---------------------------------------------------------------------------

  defp now, do: :persistent_term.get({@table, :clock}).()

  # ---------------------------------------------------------------------------
  # GenServer callbacks
  # ---------------------------------------------------------------------------

  @impl GenServer
  def init(opts) do
    clock = Keyword.get(opts, :clock, fn -> System.system_time(:second) end)
    :persistent_term.put({@table, :clock}, clock)

    :ets.new(@table, [
      :ordered_set,
      :named_table,
      :public,
      read_concurrency: true,
      write_concurrency: true
    ])

    {:ok, %{clock: clock}}
  end
end
```

Give me only the `@spec` attribute — the attribute alone (however many
lines it spans), not the whole module.
