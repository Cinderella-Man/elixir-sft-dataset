# Fill in the middle: `BiMultiMap.remove_assoc/3`

Implement the private `remove_assoc/3` helper. It takes an index `map` (either the
forward `key => MapSet of values` index or the reverse `value => MapSet of keys`
index), a lookup term `k`, and a `member` to drop. Look up `k` in `map`: if it is
absent (`Map.fetch/2` returns `:error`), return the `map` unchanged. If it is
present, delete `member` from the associated `MapSet`; if the set is now empty,
remove `k` from the `map` entirely (so no stale empty set is ever left behind),
otherwise store the shrunken set back under `k`. Return the updated `map`.

```elixir
defmodule BiMultiMap do
  @moduledoc """
  A GenServer maintaining a bidirectional **many-to-many** relation between keys
  and values.

  A key may be associated with many values and a value with many keys; the
  relation is a set of `{key, value}` pairs. A forward index (`key => MapSet of
  values`) and a reverse index (`value => MapSet of keys`) are kept perfectly in
  sync: an association is present in both directions or in neither. Empty sets are
  pruned so a key/value with no associations disappears from its index entirely.

  Keys and values may be any term.
  """

  use GenServer

  ## Client API

  @doc """
  Starts the BiMultiMap process. Accepts a `:name` option used to register it.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    {name, opts} = Keyword.pop(opts, :name)
    GenServer.start_link(__MODULE__, :ok, [name: name] ++ opts)
  end

  @doc "Records the association `{key, value}`. Idempotent. Returns `:ok`."
  @spec put(GenServer.server(), term(), term()) :: :ok
  def put(name, key, value), do: GenServer.call(name, {:put, key, value})

  @doc "Returns whether the association `{key, value}` is currently present."
  @spec member?(GenServer.server(), term(), term()) :: boolean()
  def member?(name, key, value), do: GenServer.call(name, {:member?, key, value})

  @doc "Returns a `MapSet` of all values associated with `key` (empty if none)."
  @spec get_by_key(GenServer.server(), term()) :: MapSet.t()
  def get_by_key(name, key), do: GenServer.call(name, {:get_by_key, key})

  @doc "Returns a `MapSet` of all keys associated with `value` (empty if none)."
  @spec get_by_value(GenServer.server(), term()) :: MapSet.t()
  def get_by_value(name, value), do: GenServer.call(name, {:get_by_value, value})

  @doc "Removes the single association `{key, value}` in both directions."
  @spec delete(GenServer.server(), term(), term()) :: :ok
  def delete(name, key, value), do: GenServer.call(name, {:delete, key, value})

  @doc "Removes `key` and all of its associations. Returns `:ok`."
  @spec delete_key(GenServer.server(), term()) :: :ok
  def delete_key(name, key), do: GenServer.call(name, {:delete_key, key})

  @doc "Removes `value` and all of its associations. Returns `:ok`."
  @spec delete_value(GenServer.server(), term()) :: :ok
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

  defp remove_assoc(map, k, member) do
    # TODO
  end
end
```