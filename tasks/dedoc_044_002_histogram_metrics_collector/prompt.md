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
  @default_buckets [10, 50, 100, 500, 1000]

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  def start_link(opts \\ []) do
    {name, init_opts} = Keyword.pop(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, init_opts, name: name)
  end

  def observe(name, value) when is_integer(value) and value >= 0 do
    :ets.update_counter(@table, {name, :count}, {2, 1}, {{name, :count}, 0})
    :ets.update_counter(@table, {name, :sum}, {2, value}, {{name, :sum}, 0})
    u = bucket_for(value)
    :ets.update_counter(@table, {name, :bucket, u}, {2, 1}, {{name, :bucket, u}, 0})
    :ok
  end

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
