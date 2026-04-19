defmodule LRUCacheTest do
  use ExUnit.Case, async: false

  # --- Deterministic monotonically-increasing clock ---

  defmodule Clock do
    use Agent

    def start_link(initial \\ 0) do
      Agent.start_link(fn -> initial end, name: __MODULE__)
    end

    # Every call to `now/0` returns a strictly-greater value — this models
    # a true monotonic clock and makes access ordering deterministic.
    def now do
      Agent.get_and_update(__MODULE__, fn n -> {n, n + 1} end)
    end

    def set(n), do: Agent.update(__MODULE__, fn _ -> n end)
    def current, do: Agent.get(__MODULE__, & &1)
  end

  setup do
    start_supervised!({Clock, 0})

    {:ok, pid} = LRUCache.start_link(capacity: 3, clock: &Clock.now/0)

    %{lru: pid}
  end

  # -------------------------------------------------------
  # Basic put/get/delete
  # -------------------------------------------------------

  test "put / get round-trip", %{lru: c} do
    :ok = LRUCache.put(c, :a, 1)
    :ok = LRUCache.put(c, :b, 2)

    assert {:ok, 1} = LRUCache.get(c, :a)
    assert {:ok, 2} = LRUCache.get(c, :b)
  end

  test "get on a missing key returns :miss", %{lru: c} do
    assert :miss = LRUCache.get(c, :nope)
  end

  test "delete removes the key", %{lru: c} do
    LRUCache.put(c, :a, 1)
    :ok = LRUCache.delete(c, :a)
    assert :miss = LRUCache.get(c, :a)
  end

  test "delete on missing key returns :ok", %{lru: c} do
    assert :ok = LRUCache.delete(c, :ghost)
  end

  # -------------------------------------------------------
  # Capacity enforcement
  # -------------------------------------------------------

  test "size never exceeds capacity", %{lru: c} do
    for i <- 1..10, do: LRUCache.put(c, i, i * 10)
    assert LRUCache.size(c) == 3
  end

  test "start_link rejects zero or negative capacity" do
    assert_raise ArgumentError, fn -> LRUCache.start_link(capacity: 0) end
    assert_raise ArgumentError, fn -> LRUCache.start_link(capacity: -1) end
  end

  # -------------------------------------------------------
  # LRU eviction — the defining property
  # -------------------------------------------------------

  test "new put evicts the least-recently-used entry", %{lru: c} do
    LRUCache.put(c, :a, 1)
    LRUCache.put(c, :b, 2)
    LRUCache.put(c, :c, 3)

    # Cache is full.  Inserting :d must evict :a (oldest).
    LRUCache.put(c, :d, 4)

    assert :miss = LRUCache.get(c, :a)
    assert {:ok, 2} = LRUCache.get(c, :b)
    assert {:ok, 3} = LRUCache.get(c, :c)
    assert {:ok, 4} = LRUCache.get(c, :d)
  end

  test "get refreshes access timestamp — key becomes most-recently-used", %{lru: c} do
    LRUCache.put(c, :a, 1)
    LRUCache.put(c, :b, 2)
    LRUCache.put(c, :c, 3)

    # Touch :a so it's MRU; oldest is now :b
    assert {:ok, 1} = LRUCache.get(c, :a)

    # Inserting :d now must evict :b, not :a
    LRUCache.put(c, :d, 4)

    assert {:ok, 1} = LRUCache.get(c, :a)
    assert :miss = LRUCache.get(c, :b)
    assert {:ok, 3} = LRUCache.get(c, :c)
    assert {:ok, 4} = LRUCache.get(c, :d)
  end

  test "put on an existing key never evicts another key", %{lru: c} do
    LRUCache.put(c, :a, 1)
    LRUCache.put(c, :b, 2)
    LRUCache.put(c, :c, 3)

    # Overwriting :a should NOT evict :b or :c
    LRUCache.put(c, :a, 99)

    assert LRUCache.size(c) == 3
    assert {:ok, 99} = LRUCache.get(c, :a)
    assert {:ok, 2} = LRUCache.get(c, :b)
    assert {:ok, 3} = LRUCache.get(c, :c)
  end

  test "put on an existing key updates both value AND access timestamp", %{lru: c} do
    LRUCache.put(c, :a, 1)
    LRUCache.put(c, :b, 2)
    LRUCache.put(c, :c, 3)

    # Overwrite :a — makes it MRU, oldest is now :b
    LRUCache.put(c, :a, 99)

    # Next new-key insert must evict :b
    LRUCache.put(c, :d, 4)

    assert {:ok, 99} = LRUCache.get(c, :a)
    assert :miss = LRUCache.get(c, :b)
  end

  test "missing get does NOT refresh anything", %{lru: c} do
    LRUCache.put(c, :a, 1)
    LRUCache.put(c, :b, 2)
    LRUCache.put(c, :c, 3)

    # A miss shouldn't change anything
    assert :miss = LRUCache.get(c, :nope)

    # Oldest is still :a, so this evicts :a
    LRUCache.put(c, :d, 4)
    assert :miss = LRUCache.get(c, :a)
  end

  test "delete does NOT refresh timestamps and allows future insert without eviction", %{lru: c} do
    LRUCache.put(c, :a, 1)
    LRUCache.put(c, :b, 2)
    LRUCache.put(c, :c, 3)

    LRUCache.delete(c, :b)
    assert LRUCache.size(c) == 2

    # Capacity is 3; we have 2 entries; inserting :d should not evict anything
    LRUCache.put(c, :d, 4)

    assert {:ok, 1} = LRUCache.get(c, :a)
    assert :miss = LRUCache.get(c, :b)
    assert {:ok, 3} = LRUCache.get(c, :c)
    assert {:ok, 4} = LRUCache.get(c, :d)
  end

  # -------------------------------------------------------
  # keys_by_recency inspection
  # -------------------------------------------------------

  test "keys_by_recency returns MRU first, LRU last", %{lru: c} do
    LRUCache.put(c, :a, 1)
    LRUCache.put(c, :b, 2)
    LRUCache.put(c, :c, 3)

    assert [:c, :b, :a] = LRUCache.keys_by_recency(c)

    LRUCache.get(c, :a)
    assert [:a, :c, :b] = LRUCache.keys_by_recency(c)

    LRUCache.put(c, :b, 99)
    assert [:b, :a, :c] = LRUCache.keys_by_recency(c)
  end

  # -------------------------------------------------------
  # Longer trace
  # -------------------------------------------------------

  test "longer sequence produces the expected LRU evictions" do
    # Clock is already started by setup — reset it instead of starting again.
    Clock.set(0)

    {:ok, c} = LRUCache.start_link(capacity: 3, clock: &Clock.now/0)

    # Standard LRU textbook trace.
    LRUCache.put(c, :a, 1)         # [:a]
    LRUCache.put(c, :b, 2)         # [:b, :a]
    LRUCache.put(c, :c, 3)         # [:c, :b, :a]
    LRUCache.get(c, :a)            # [:a, :c, :b]
    LRUCache.put(c, :d, 4)         # evicts :b → [:d, :a, :c]
    LRUCache.get(c, :c)            # [:c, :d, :a]
    LRUCache.put(c, :e, 5)         # evicts :a → [:e, :c, :d]

    assert :miss = LRUCache.get(c, :b)
    assert :miss = LRUCache.get(c, :a)
    assert {:ok, 3} = LRUCache.get(c, :c)
    assert {:ok, 4} = LRUCache.get(c, :d)
    assert {:ok, 5} = LRUCache.get(c, :e)
  end
end
