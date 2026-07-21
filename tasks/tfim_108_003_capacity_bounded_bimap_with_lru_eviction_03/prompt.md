# Fill in the middle: implement the blanked test

Below is a module and its ExUnit test harness with the body of ONE `test` removed
(marked `# TODO`). The test's name states what it must verify. Implement just that one
test so the harness passes for a correct implementation of the module.

## Module under test

```elixir
defmodule BoundedBiMap do
  @moduledoc """
  A GenServer maintaining a bijective bidirectional mapping bounded to a fixed
  `:capacity`, with least-recently-used (LRU) eviction.

  State holds a forward map (`key => value`), a reverse map (`value => key`), and
  an access map (`key => tick`) tracking recency via a monotonic clock. Every
  `put` and every successful `get_by_key`/`get_by_value` refreshes a pair's
  recency. When a brand-new key is inserted while the map is at capacity, the
  least-recently-used pair is evicted first.

  Keys and values may be any term.
  """

  use GenServer

  ## Client API

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    {name, opts} = Keyword.pop(opts, :name)
    {capacity, opts} = Keyword.pop(opts, :capacity)
    GenServer.start_link(__MODULE__, capacity, [name: name] ++ opts)
  end

  @doc "Stores the `key`<->`value` pair, evicting the LRU entry when at capacity. Returns `:ok`."
  @spec put(GenServer.server(), term(), term()) :: :ok
  def put(name, key, value), do: GenServer.call(name, {:put, key, value})

  @spec get_by_key(GenServer.server(), term()) :: {:ok, term()} | :error
  def get_by_key(name, key), do: GenServer.call(name, {:get_by_key, key})

  @spec get_by_value(GenServer.server(), term()) :: {:ok, term()} | :error
  def get_by_value(name, value), do: GenServer.call(name, {:get_by_value, value})

  @spec delete(GenServer.server(), term()) :: :ok
  def delete(name, key), do: GenServer.call(name, {:delete, key})

  @spec size(GenServer.server()) :: non_neg_integer()
  def size(name), do: GenServer.call(name, :size)

  @spec keys_by_recency(GenServer.server()) :: [term()]
  def keys_by_recency(name), do: GenServer.call(name, :keys_by_recency)

  ## Server callbacks

  @impl true
  def init(capacity) when is_integer(capacity) and capacity > 0 do
    {:ok, %{forward: %{}, reverse: %{}, access: %{}, clock: 0, capacity: capacity}}
  end

  @impl true
  def handle_call({:put, key, value}, _from, state) do
    %{forward: f, reverse: r, access: a, clock: c, capacity: cap} = state

    key_existed = Map.has_key?(f, key)

    # Bijection maintenance step 1: if key rebinds to a new value, orphan old value.
    r =
      case Map.fetch(f, key) do
        {:ok, ^value} -> r
        {:ok, oldv} -> Map.delete(r, oldv)
        :error -> r
      end

    # Bijection maintenance step 2: if value rebinds to a new key, evict old key.
    {f, r, a} =
      case Map.fetch(r, value) do
        {:ok, ^key} -> {f, r, a}
        {:ok, oldk} -> {Map.delete(f, oldk), r, Map.delete(a, oldk)}
        :error -> {f, r, a}
      end

    # LRU eviction only when a genuinely new key would push us past capacity.
    {f, r, a} =
      if not key_existed and map_size(f) >= cap do
        evict_lru(f, r, a)
      else
        {f, r, a}
      end

    f = Map.put(f, key, value)
    r = Map.put(r, value, key)
    a = Map.put(a, key, c)

    {:reply, :ok, %{state | forward: f, reverse: r, access: a, clock: c + 1}}
  end

  def handle_call({:get_by_key, key}, _from, state) do
    case Map.fetch(state.forward, key) do
      {:ok, v} -> {:reply, {:ok, v}, touch(state, key)}
      :error -> {:reply, :error, state}
    end
  end

  def handle_call({:get_by_value, value}, _from, state) do
    case Map.fetch(state.reverse, value) do
      {:ok, k} -> {:reply, {:ok, k}, touch(state, k)}
      :error -> {:reply, :error, state}
    end
  end

  def handle_call({:delete, key}, _from, state) do
    case Map.fetch(state.forward, key) do
      {:ok, v} ->
        new_state = %{
          state
          | forward: Map.delete(state.forward, key),
            reverse: Map.delete(state.reverse, v),
            access: Map.delete(state.access, key)
        }

        {:reply, :ok, new_state}

      :error ->
        {:reply, :ok, state}
    end
  end

  def handle_call(:size, _from, state), do: {:reply, map_size(state.forward), state}

  def handle_call(:keys_by_recency, _from, state) do
    keys =
      state.access
      |> Enum.sort_by(fn {_k, tick} -> tick end)
      |> Enum.map(fn {k, _tick} -> k end)

    {:reply, keys, state}
  end

  ## Helpers

  defp touch(state, key) do
    %{state | access: Map.put(state.access, key, state.clock), clock: state.clock + 1}
  end

  defp evict_lru(f, r, a) do
    {lru_key, _tick} = Enum.min_by(a, fn {_k, tick} -> tick end)
    value = Map.fetch!(f, lru_key)
    {Map.delete(f, lru_key), Map.delete(r, value), Map.delete(a, lru_key)}
  end
end
```

## Test harness — implement the `# TODO` test

```elixir
defmodule BoundedBiMapTest do
  use ExUnit.Case, async: false

  setup context do
    name = :"bbm_#{System.unique_integer([:positive])}"
    capacity = Map.get(context, :capacity, 3)
    pid = start_supervised!({BoundedBiMap, name: name, capacity: capacity})
    %{bm: name, pid: pid, capacity: capacity}
  end

  # -------------------------------------------------------
  # Basic bijection behavior (inherited)
  # -------------------------------------------------------

  test "put then look up in both directions", %{bm: bm} do
    assert :ok = BoundedBiMap.put(bm, :a, 1)
    assert {:ok, 1} = BoundedBiMap.get_by_key(bm, :a)
    assert {:ok, :a} = BoundedBiMap.get_by_value(bm, 1)
  end

  test "missing key and value return :error", %{bm: bm} do
    # TODO
  end

  test "reassigning a key orphans the old value", %{bm: bm} do
    BoundedBiMap.put(bm, :a, 1)
    BoundedBiMap.put(bm, :a, 2)

    assert :error = BoundedBiMap.get_by_value(bm, 1)
    assert {:ok, 2} = BoundedBiMap.get_by_key(bm, :a)
    assert {:ok, :a} = BoundedBiMap.get_by_value(bm, 2)
  end

  # -------------------------------------------------------
  # Capacity is never exceeded
  # -------------------------------------------------------

  @tag capacity: 3
  test "size never exceeds capacity", %{bm: bm} do
    for i <- 1..10 do
      BoundedBiMap.put(bm, :"k#{i}", i)
      assert BoundedBiMap.size(bm) <= 3
    end

    assert BoundedBiMap.size(bm) == 3
  end

  # -------------------------------------------------------
  # LRU eviction: textbook trace
  # -------------------------------------------------------

  @tag capacity: 3
  test "new-key insertion at capacity evicts the LRU pair", %{bm: bm} do
    BoundedBiMap.put(bm, :a, 1)
    BoundedBiMap.put(bm, :b, 2)
    BoundedBiMap.put(bm, :c, 3)

    # Touch :a so it becomes most-recently-used; :b is now the LRU.
    assert {:ok, 1} = BoundedBiMap.get_by_key(bm, :a)

    # Inserting a brand-new key at capacity evicts :b.
    BoundedBiMap.put(bm, :d, 4)

    assert :error = BoundedBiMap.get_by_key(bm, :b)
    assert :error = BoundedBiMap.get_by_value(bm, 2)
    assert {:ok, 1} = BoundedBiMap.get_by_key(bm, :a)
    assert {:ok, 3} = BoundedBiMap.get_by_key(bm, :c)
    assert {:ok, 4} = BoundedBiMap.get_by_key(bm, :d)
  end

  @tag capacity: 2
  test "get_by_value refreshes recency and protects a pair from eviction", %{bm: bm} do
    BoundedBiMap.put(bm, :a, 1)
    BoundedBiMap.put(bm, :b, 2)

    # Access :a via the value side; :b becomes the LRU.
    assert {:ok, :a} = BoundedBiMap.get_by_value(bm, 1)

    BoundedBiMap.put(bm, :c, 3)

    assert :error = BoundedBiMap.get_by_key(bm, :b)
    assert {:ok, 1} = BoundedBiMap.get_by_key(bm, :a)
    assert {:ok, 3} = BoundedBiMap.get_by_key(bm, :c)
  end

  # -------------------------------------------------------
  # Overwriting an existing key never evicts
  # -------------------------------------------------------

  @tag capacity: 2
  test "overwriting an existing key does not evict another pair", %{bm: bm} do
    BoundedBiMap.put(bm, :a, 1)
    BoundedBiMap.put(bm, :b, 2)

    # Overwrite :a's value; count stays 2, nothing is evicted.
    BoundedBiMap.put(bm, :a, 9)

    assert BoundedBiMap.size(bm) == 2
    assert {:ok, 9} = BoundedBiMap.get_by_key(bm, :a)
    assert {:ok, 2} = BoundedBiMap.get_by_key(bm, :b)
    # The old value is orphaned by bijection maintenance.
    assert :error = BoundedBiMap.get_by_value(bm, 1)
  end

  # -------------------------------------------------------
  # Every put refreshes recency, overwrites included
  # -------------------------------------------------------

  @tag capacity: 3
  test "overwriting a key makes it MRU and shifts the next eviction victim", %{bm: bm} do
    BoundedBiMap.put(bm, :a, 1)
    BoundedBiMap.put(bm, :b, 2)
    BoundedBiMap.put(bm, :c, 3)

    # :a is the LRU until its value is overwritten; the overwrite refreshes it.
    BoundedBiMap.put(bm, :a, 9)

    assert [:b, :c, :a] == BoundedBiMap.keys_by_recency(bm)

    # A brand-new key at capacity now evicts :b, not the freshly written :a.
    BoundedBiMap.put(bm, :d, 4)

    assert :error = BoundedBiMap.get_by_key(bm, :b)
    assert :error = BoundedBiMap.get_by_value(bm, 2)
    assert {:ok, 9} = BoundedBiMap.get_by_key(bm, :a)
    assert {:ok, :a} = BoundedBiMap.get_by_value(bm, 9)
    assert {:ok, 3} = BoundedBiMap.get_by_key(bm, :c)
    assert {:ok, 4} = BoundedBiMap.get_by_key(bm, :d)
    assert BoundedBiMap.size(bm) == 3
  end

  @tag capacity: 3
  test "re-putting an unchanged pair refreshes recency and shifts the victim", %{bm: bm} do
    BoundedBiMap.put(bm, :a, 1)
    BoundedBiMap.put(bm, :b, 2)
    BoundedBiMap.put(bm, :c, 3)

    # Writing the identical pair still counts as using it.
    BoundedBiMap.put(bm, :a, 1)

    assert [:b, :c, :a] == BoundedBiMap.keys_by_recency(bm)

    BoundedBiMap.put(bm, :d, 4)

    assert :error = BoundedBiMap.get_by_key(bm, :b)
    assert {:ok, 1} = BoundedBiMap.get_by_key(bm, :a)
    assert {:ok, :a} = BoundedBiMap.get_by_value(bm, 1)
    assert BoundedBiMap.size(bm) == 3
  end

  # -------------------------------------------------------
  # Value collision frees a slot instead of LRU-evicting
  # -------------------------------------------------------

  @tag capacity: 2
  test "value collision removes the old key and needs no LRU eviction", %{bm: bm} do
    BoundedBiMap.put(bm, :a, 1)
    BoundedBiMap.put(bm, :b, 2)

    # New key :c takes value 1, which currently belongs to :a.
    # :a is removed (bijection), which frees a slot; :b must survive.
    BoundedBiMap.put(bm, :c, 1)

    assert :error = BoundedBiMap.get_by_key(bm, :a)
    assert {:ok, :c} = BoundedBiMap.get_by_value(bm, 1)
    assert {:ok, 2} = BoundedBiMap.get_by_key(bm, :b)
    assert BoundedBiMap.size(bm) == 2
  end

  # -------------------------------------------------------
  # delete frees capacity headroom
  # -------------------------------------------------------

  @tag capacity: 2
  test "delete frees a slot so the next new key doesn't evict", %{bm: bm} do
    BoundedBiMap.put(bm, :a, 1)
    BoundedBiMap.put(bm, :b, 2)

    assert :ok = BoundedBiMap.delete(bm, :a)
    assert :error = BoundedBiMap.get_by_key(bm, :a)
    assert :error = BoundedBiMap.get_by_value(bm, 1)

    BoundedBiMap.put(bm, :c, 3)

    # :b was never evicted because delete made room.
    assert {:ok, 2} = BoundedBiMap.get_by_key(bm, :b)
    assert {:ok, 3} = BoundedBiMap.get_by_key(bm, :c)
  end

  test "delete of an absent key is a harmless no-op", %{bm: bm} do
    assert :ok = BoundedBiMap.delete(bm, :ghost)
    BoundedBiMap.put(bm, :a, 1)
    assert :ok = BoundedBiMap.delete(bm, :ghost)
    assert {:ok, 1} = BoundedBiMap.get_by_key(bm, :a)
  end

  # -------------------------------------------------------
  # keys_by_recency inspection
  # -------------------------------------------------------

  @tag capacity: 3
  test "keys_by_recency orders LRU-first, MRU-last", %{bm: bm} do
    BoundedBiMap.put(bm, :a, 1)
    BoundedBiMap.put(bm, :b, 2)
    BoundedBiMap.put(bm, :c, 3)

    # Touch :a to move it to MRU.
    BoundedBiMap.get_by_key(bm, :a)

    assert [:b, :c, :a] == BoundedBiMap.keys_by_recency(bm)
  end
end
```
