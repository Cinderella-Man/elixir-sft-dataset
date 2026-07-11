# Fill in the middle: implement the blanked test

Below is a module and its ExUnit test harness with the body of ONE `test` removed
(marked `# TODO`). The test's name states what it must verify. Implement just that one
test so the harness passes for a correct implementation of the module.

## Module under test

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

## Test harness — implement the `# TODO` test

```elixir
defmodule BiMultiMapTest do
  use ExUnit.Case, async: false

  setup do
    name = :"bimm_#{System.unique_integer([:positive])}"
    pid = start_supervised!({BiMultiMap, name: name})
    %{bm: name, pid: pid}
  end

  # -------------------------------------------------------
  # Basic association and both-direction lookup
  # -------------------------------------------------------

  test "put then look up in both directions", %{bm: bm} do
    assert :ok = BiMultiMap.put(bm, :a, 1)

    assert MapSet.new([1]) == BiMultiMap.get_by_key(bm, :a)
    assert MapSet.new([:a]) == BiMultiMap.get_by_value(bm, 1)
    assert BiMultiMap.member?(bm, :a, 1)
  end

  test "missing key and value return empty sets", %{bm: bm} do
    assert MapSet.new() == BiMultiMap.get_by_key(bm, :nope)
    assert MapSet.new() == BiMultiMap.get_by_value(bm, 999)
    refute BiMultiMap.member?(bm, :nope, 999)
  end

  # -------------------------------------------------------
  # One key -> many values
  # -------------------------------------------------------

  test "a key may hold many values", %{bm: bm} do
    BiMultiMap.put(bm, :a, 1)
    BiMultiMap.put(bm, :a, 2)
    BiMultiMap.put(bm, :a, 3)

    assert MapSet.new([1, 2, 3]) == BiMultiMap.get_by_key(bm, :a)
    assert MapSet.new([:a]) == BiMultiMap.get_by_value(bm, 1)
    assert MapSet.new([:a]) == BiMultiMap.get_by_value(bm, 2)
  end

  # -------------------------------------------------------
  # One value -> many keys (this is what makes it NOT a bijection)
  # -------------------------------------------------------

  test "a value may be shared by many keys without evicting", %{bm: bm} do
    BiMultiMap.put(bm, :a, 1)
    BiMultiMap.put(bm, :b, 1)
    BiMultiMap.put(bm, :c, 1)

    # Unlike the bijective BiMap, the earlier keys survive.
    assert MapSet.new([:a, :b, :c]) == BiMultiMap.get_by_value(bm, 1)
    assert MapSet.new([1]) == BiMultiMap.get_by_key(bm, :a)
    assert MapSet.new([1]) == BiMultiMap.get_by_key(bm, :b)
  end

  test "full many-to-many mesh stays consistent", %{bm: bm} do
    for k <- [:a, :b], v <- [1, 2] do
      BiMultiMap.put(bm, k, v)
    end

    assert MapSet.new([1, 2]) == BiMultiMap.get_by_key(bm, :a)
    assert MapSet.new([1, 2]) == BiMultiMap.get_by_key(bm, :b)
    assert MapSet.new([:a, :b]) == BiMultiMap.get_by_value(bm, 1)
    assert MapSet.new([:a, :b]) == BiMultiMap.get_by_value(bm, 2)
  end

  # -------------------------------------------------------
  # Idempotency
  # -------------------------------------------------------

  test "putting the same pair twice is a no-op", %{bm: bm} do
    BiMultiMap.put(bm, :a, 1)
    BiMultiMap.put(bm, :a, 1)

    assert MapSet.new([1]) == BiMultiMap.get_by_key(bm, :a)
    assert MapSet.new([:a]) == BiMultiMap.get_by_value(bm, 1)
  end

  # -------------------------------------------------------
  # Single-association delete
  # -------------------------------------------------------

  test "delete removes just one association in both directions", %{bm: bm} do
    BiMultiMap.put(bm, :a, 1)
    BiMultiMap.put(bm, :a, 2)

    assert :ok = BiMultiMap.delete(bm, :a, 1)

    refute BiMultiMap.member?(bm, :a, 1)
    assert BiMultiMap.member?(bm, :a, 2)
    assert MapSet.new([2]) == BiMultiMap.get_by_key(bm, :a)
    assert MapSet.new() == BiMultiMap.get_by_value(bm, 1)
  end

  test "removing the last value prunes the key entirely", %{bm: bm} do
    BiMultiMap.put(bm, :a, 1)
    BiMultiMap.delete(bm, :a, 1)

    assert MapSet.new() == BiMultiMap.get_by_key(bm, :a)
    assert MapSet.new() == BiMultiMap.get_by_value(bm, 1)
  end

  test "deleting an absent association is a harmless no-op", %{bm: bm} do
    # TODO
  end

  # -------------------------------------------------------
  # delete_key / delete_value
  # -------------------------------------------------------

  test "delete_key removes the key and cleans every reverse entry", %{bm: bm} do
    BiMultiMap.put(bm, :a, 1)
    BiMultiMap.put(bm, :a, 2)
    BiMultiMap.put(bm, :b, 1)

    assert :ok = BiMultiMap.delete_key(bm, :a)

    assert MapSet.new() == BiMultiMap.get_by_key(bm, :a)
    # value 1 is still held by :b, but no longer by :a
    assert MapSet.new([:b]) == BiMultiMap.get_by_value(bm, 1)
    # value 2 had only :a, so it's now empty
    assert MapSet.new() == BiMultiMap.get_by_value(bm, 2)
  end

  test "delete_value removes the value and cleans every forward entry", %{bm: bm} do
    BiMultiMap.put(bm, :a, 1)
    BiMultiMap.put(bm, :b, 1)
    BiMultiMap.put(bm, :a, 2)

    assert :ok = BiMultiMap.delete_value(bm, 1)

    assert MapSet.new() == BiMultiMap.get_by_value(bm, 1)
    assert MapSet.new([2]) == BiMultiMap.get_by_key(bm, :a)
    # :b only had value 1, so it's now empty
    assert MapSet.new() == BiMultiMap.get_by_key(bm, :b)
  end

  # -------------------------------------------------------
  # Consistency fuzz across a mixed operation sequence
  # -------------------------------------------------------

  test "forward/reverse consistency holds across a mixed sequence", %{bm: bm} do
    ops = [
      {:put, :a, 1},
      {:put, :a, 2},
      {:put, :b, 1},
      {:put, :c, 3},
      {:delete, :a, 1},
      {:put, :b, 2},
      {:delete_value, 3},
      {:put, :c, 2},
      {:delete_key, :a},
      {:put, :d, 1}
    ]

    Enum.each(ops, fn
      {:put, k, v} -> assert :ok = BiMultiMap.put(bm, k, v)
      {:delete, k, v} -> assert :ok = BiMultiMap.delete(bm, k, v)
      {:delete_key, k} -> assert :ok = BiMultiMap.delete_key(bm, k)
      {:delete_value, v} -> assert :ok = BiMultiMap.delete_value(bm, v)
    end)

    keys = [:a, :b, :c, :d]
    values = [1, 2, 3]

    # Every forward association must be mirrored in the reverse index.
    for k <- keys, v <- BiMultiMap.get_by_key(bm, k) do
      assert MapSet.member?(BiMultiMap.get_by_value(bm, v), k)
      assert BiMultiMap.member?(bm, k, v)
    end

    # Every reverse association must be mirrored in the forward index.
    for v <- values, k <- BiMultiMap.get_by_value(bm, v) do
      assert MapSet.member?(BiMultiMap.get_by_key(bm, k), v)
      assert BiMultiMap.member?(bm, k, v)
    end
  end
end
```
