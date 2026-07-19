# Write the missing @spec

Below is a complete, working module — except that the `@spec` for
`delete_key/2` has been removed; its place is marked `# TODO: @spec`.
Write exactly that typespec: one `@spec` attribute for `delete_key/2`,
consistent with the function's arguments, guards, and every return shape
the implementation can produce. Change nothing else.

## The module with the `@spec` for `delete_key/2` missing

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
  # TODO: @spec
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

Give me only the `@spec` attribute — the attribute alone (however many
lines it spans), not the whole module.
