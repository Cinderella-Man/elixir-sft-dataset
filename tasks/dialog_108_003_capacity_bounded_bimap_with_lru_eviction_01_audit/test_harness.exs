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
    assert :error = BoundedBiMap.get_by_key(bm, :nope)
    assert :error = BoundedBiMap.get_by_value(bm, 999)
  end

  test "reassigning a key orphans the old value", %{bm: bm} do
    BoundedBiMap.put(bm, :a, 1)
    BoundedBiMap.put(bm, :a, 2)

    assert :error = BoundedBiMap.get_by_value(bm, 1)
    assert {:ok, 2} = BoundedBiMap.get_by_key(bm, :a)
    assert {:ok, :a} = BoundedBiMap.get_by_value(bm, 2)
  end

  test "arbitrary terms work as keys and values", %{bm: bm} do
    key = {:tuple, [1, 2], %{nested: true}}
    value = %{"str" => <<1, 2, 3>>}

    assert :ok = BoundedBiMap.put(bm, key, value)
    assert {:ok, ^value} = BoundedBiMap.get_by_key(bm, key)
    assert {:ok, ^key} = BoundedBiMap.get_by_value(bm, value)
    assert BoundedBiMap.size(bm) == 1
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

  @tag capacity: 3
  test "put refreshes recency, protecting the re-put pair from the next eviction", %{bm: bm} do
    BoundedBiMap.put(bm, :a, 1)
    BoundedBiMap.put(bm, :b, 2)
    BoundedBiMap.put(bm, :c, 3)

    # Re-put :a with the same value; :a becomes MRU and :b becomes the LRU.
    BoundedBiMap.put(bm, :a, 1)
    assert BoundedBiMap.size(bm) == 3

    BoundedBiMap.put(bm, :d, 4)

    assert :error = BoundedBiMap.get_by_key(bm, :b)
    assert {:ok, 1} = BoundedBiMap.get_by_key(bm, :a)
    assert {:ok, 3} = BoundedBiMap.get_by_key(bm, :c)
    assert {:ok, 4} = BoundedBiMap.get_by_key(bm, :d)
  end

  @tag capacity: 2
  test "failed lookups do not change the eviction order", %{bm: bm} do
    BoundedBiMap.put(bm, :a, 1)
    BoundedBiMap.put(bm, :b, 2)

    assert :error = BoundedBiMap.get_by_key(bm, :ghost)
    assert :error = BoundedBiMap.get_by_value(bm, :ghost)
    assert [:a, :b] == BoundedBiMap.keys_by_recency(bm)

    # :a is still the LRU, so it is the one evicted.
    BoundedBiMap.put(bm, :c, 3)

    assert :error = BoundedBiMap.get_by_key(bm, :a)
    assert {:ok, 2} = BoundedBiMap.get_by_key(bm, :b)
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
  # size and keys_by_recency inspection
  # -------------------------------------------------------

  test "size and keys_by_recency start empty and track puts and deletes", %{bm: bm} do
    assert BoundedBiMap.size(bm) == 0
    assert [] == BoundedBiMap.keys_by_recency(bm)

    BoundedBiMap.put(bm, :a, 1)
    BoundedBiMap.put(bm, :b, 2)
    assert BoundedBiMap.size(bm) == 2
    assert [:a, :b] == BoundedBiMap.keys_by_recency(bm)

    BoundedBiMap.delete(bm, :a)
    assert BoundedBiMap.size(bm) == 1
    assert [:b] == BoundedBiMap.keys_by_recency(bm)
  end

  @tag capacity: 3
  test "keys_by_recency orders LRU-first, MRU-last", %{bm: bm} do
    BoundedBiMap.put(bm, :a, 1)
    BoundedBiMap.put(bm, :b, 2)
    BoundedBiMap.put(bm, :c, 3)

    # Touch :a to move it to MRU.
    BoundedBiMap.get_by_key(bm, :a)

    assert [:b, :c, :a] == BoundedBiMap.keys_by_recency(bm)
  end

  test "start_link refuses a non-positive capacity" do
    Process.flag(:trap_exit, true)
    name = :"bbm_guard_#{System.unique_integer([:positive])}"

    assert {:error, _reason} = BoundedBiMap.start_link(name: name, capacity: 0)
  end
end
