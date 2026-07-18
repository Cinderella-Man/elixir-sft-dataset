# Document this module

Below is a complete, working, tested Elixir module. Its behavior is correct
and must not change — but every piece of documentation has been stripped.

Add the missing documentation and typespecs:

- a `@moduledoc` that explains what the module does and how it is used,
- a `@doc` for every public function,
- a `@spec` for every public function (add `@type`s where they make the
  specs clearer).

Do not change any behavior: every function clause, guard, and expression
must keep working exactly as it does now. Do not rename anything, do not
"improve" the code, and do not add or remove functions. Give me the
complete documented module in a single file.

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

  def increment(name), do: increment(name, %{}, 1)

  def increment(name, labels) when is_map(labels), do: increment(name, labels, 1)
  def increment(name, amount) when is_integer(amount), do: increment(name, %{}, amount)

  def increment(name, labels, amount)
      when is_map(labels) and is_integer(amount) and amount >= 0 do
    key = key(name, labels)
    :ets.update_counter(@table, key, {2, amount}, {key, 0})
    :ok
  end

  def gauge(name, value), do: gauge(name, %{}, value)

  def gauge(name, labels, value) when is_map(labels) do
    :ets.insert(@table, {key(name, labels), value})
    :ok
  end

  def get(name, labels) when is_map(labels) do
    case :ets.lookup(@table, key(name, labels)) do
      [{_, value}] -> value
      [] -> nil
    end
  end

  def get(name) do
    case :ets.select(@table, [{{{name, :"$1"}, :"$2"}, [], [:"$2"]}]) do
      [] -> nil
      values -> Enum.sum(values)
    end
  end

  def series(name) do
    @table
    |> :ets.select([{{{name, :"$1"}, :"$2"}, [], [{{:"$1", :"$2"}}]}])
    |> Enum.map(fn {norm, value} -> %{labels: Map.new(norm), value: value} end)
  end

  def reset(name, labels) when is_map(labels) do
    :ets.insert(@table, {key(name, labels), 0})
    :ok
  end

  def reset(name) do
    @table
    |> :ets.select([{{{name, :"$1"}, :_}, [], [:"$1"]}])
    |> Enum.each(fn norm -> :ets.insert(@table, {{name, norm}, 0}) end)

    :ok
  end

  def all do
    :ets.foldl(
      fn {{name, norm}, value}, acc -> Map.put(acc, {name, Map.new(norm)}, value) end,
      %{},
      @table
    )
  end

  # ---------------------------------------------------------------------------
  # Internal helpers
  # ---------------------------------------------------------------------------

  # Canonicalise labels to a sorted list so key/value order is irrelevant.
  defp key(name, labels), do: {name, Enum.sort(labels)}

  # ---------------------------------------------------------------------------
  # GenServer callbacks
  # ---------------------------------------------------------------------------

  @impl GenServer
  def init(_opts) do
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
