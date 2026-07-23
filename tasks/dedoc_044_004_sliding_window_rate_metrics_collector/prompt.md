# Add moduledoc, docs, and specs

Below: a correct, tested, undocumented module. Deliver the same module
fully documented — a `@moduledoc`, a per-public-function `@doc` and
`@spec`, and supporting `@type`s where useful. Behavior, names, structure:
unchanged. One file.

## The module

```elixir
defmodule Metrics do
  use GenServer

  @table __MODULE__

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  def start_link(opts \\ []) do
    {name, init_opts} = Keyword.pop(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, init_opts, name: name)
  end

  def increment(name, amount \\ 1) when is_integer(amount) and amount >= 0 do
    second = now()
    key = {name, second}
    :ets.update_counter(@table, key, {2, amount}, {key, 0})
    :ok
  end

  def rate(name, window_seconds) do
    cutoff = now() - window_seconds

    @table
    |> :ets.select([{{{name, :"$1"}, :"$2"}, [{:>, :"$1", cutoff}], [:"$2"]}])
    |> Enum.sum()
  end

  def count(name) do
    @table
    |> :ets.select([{{{name, :"$1"}, :"$2"}, [], [:"$2"]}])
    |> Enum.sum()
  end

  def reset(name) do
    :ets.match_delete(@table, {{name, :_}, :_})
    :ok
  end

  def prune(retention_seconds) do
    cutoff = now() - retention_seconds
    :ets.select_delete(@table, [{{{:_, :"$1"}, :_}, [{:"=<", :"$1", cutoff}], [true]}])
  end

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
