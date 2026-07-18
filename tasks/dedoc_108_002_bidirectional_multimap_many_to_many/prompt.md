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
defmodule BiMultiMap do
  use GenServer

  ## Client API

  def start_link(opts) do
    {name, opts} = Keyword.pop(opts, :name)
    GenServer.start_link(__MODULE__, :ok, [name: name] ++ opts)
  end

  def put(name, key, value), do: GenServer.call(name, {:put, key, value})

  def member?(name, key, value), do: GenServer.call(name, {:member?, key, value})

  def get_by_key(name, key), do: GenServer.call(name, {:get_by_key, key})

  def get_by_value(name, value), do: GenServer.call(name, {:get_by_value, value})

  def delete(name, key, value), do: GenServer.call(name, {:delete, key, value})

  def delete_key(name, key), do: GenServer.call(name, {:delete_key, key})

  def delete_value(name, value), do: GenServer.call(name, {:delete_value, value})

  ## Server callbacks

  @impl true
  def init(:ok) do
    # forward: key => MapSet of values, reverse: value => MapSet of keys
    {:ok, %{forward: %{}, reverse: %{}}}
  end

  @impl true
  def handle_call({:put, key, value}, _from, %{forward: f, reverse: r} = s) do
    f = Map.update(f, key, MapSet.new([value]), &MapSet.put(&1, value))
    r = Map.update(r, value, MapSet.new([key]), &MapSet.put(&1, key))
    {:reply, :ok, %{s | forward: f, reverse: r}}
  end

  def handle_call({:member?, key, value}, _from, s) do
    vs = Map.get(s.forward, key, MapSet.new())
    {:reply, MapSet.member?(vs, value), s}
  end

  def handle_call({:get_by_key, key}, _from, s) do
    {:reply, Map.get(s.forward, key, MapSet.new()), s}
  end

  def handle_call({:get_by_value, value}, _from, s) do
    {:reply, Map.get(s.reverse, value, MapSet.new()), s}
  end

  def handle_call({:delete, key, value}, _from, %{forward: f, reverse: r} = s) do
    f = remove_assoc(f, key, value)
    r = remove_assoc(r, value, key)
    {:reply, :ok, %{s | forward: f, reverse: r}}
  end

  def handle_call({:delete_key, key}, _from, %{forward: f, reverse: r} = s) do
    values = Map.get(f, key, MapSet.new())
    r = Enum.reduce(values, r, fn v, r -> remove_assoc(r, v, key) end)
    {:reply, :ok, %{s | forward: Map.delete(f, key), reverse: r}}
  end

  def handle_call({:delete_value, value}, _from, %{forward: f, reverse: r} = s) do
    keys = Map.get(r, value, MapSet.new())
    f = Enum.reduce(keys, f, fn k, f -> remove_assoc(f, k, value) end)
    {:reply, :ok, %{s | forward: f, reverse: Map.delete(r, value)}}
  end

  # Drops `member` from the set stored at `k`, pruning the key when it empties.
  defp remove_assoc(map, k, member) do
    case Map.fetch(map, k) do
      {:ok, set} ->
        set = MapSet.delete(set, member)
        if MapSet.size(set) == 0, do: Map.delete(map, k), else: Map.put(map, k, set)

      :error ->
        map
    end
  end
end
```
