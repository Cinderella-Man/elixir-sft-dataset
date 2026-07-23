# Add moduledoc, docs, and specs

Below: a correct, tested, undocumented module. Deliver the same module
fully documented — a `@moduledoc`, a per-public-function `@doc` and
`@spec`, and supporting `@type`s where useful. Behavior, names, structure:
unchanged. One file.

## The module

```elixir
defmodule Metrics do
  use GenServer

  # The ETS table name is fixed and module-scoped.  Because the table is
  # :public and :named_table every caller can hit it directly without
  # routing through the owning process.
  @table __MODULE__

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  def start_link(opts \\ []) do
    {name, init_opts} = Keyword.pop(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, init_opts, name: name)
  end

  def increment(name, amount \\ 1) when is_integer(amount) and amount >= 0 do
    :ets.update_counter(@table, name, {2, amount}, {name, 0})
    :ok
  end

  def gauge(name, value) do
    :ets.insert(@table, {name, value})
    :ok
  end

  def get(name) do
    case :ets.lookup(@table, name) do
      [{^name, value}] -> value
      [] -> nil
    end
  end

  def all do
    :ets.tab2list(@table)
    |> Map.new()
  end

  def snapshot, do: all()

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
