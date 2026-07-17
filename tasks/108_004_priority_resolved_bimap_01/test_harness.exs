defmodule PriorityBiMapTest do
  use ExUnit.Case, async: false

  setup do
    name = :"pbm_#{System.unique_integer([:positive])}"
    pid = start_supervised!({PriorityBiMap, name: name})
    %{bm: name, pid: pid}
  end

  # -------------------------------------------------------
  # Basic install and lookup
  # -------------------------------------------------------

  test "put then look up in both directions", %{bm: bm} do
    assert {:ok, []} = PriorityBiMap.put(bm, :a, 1, 10)

    assert {:ok, 1} = PriorityBiMap.get_by_key(bm, :a)
    assert {:ok, :a} = PriorityBiMap.get_by_value(bm, 1)
    assert {:ok, 10} = PriorityBiMap.priority(bm, :a)
  end

  test "missing key/value/priority return :error", %{bm: bm} do
    assert :error = PriorityBiMap.get_by_key(bm, :nope)
    assert :error = PriorityBiMap.get_by_value(bm, 999)
    assert :error = PriorityBiMap.priority(bm, :nope)
  end

  test "non-conflicting pairs install cleanly", %{bm: bm} do
    assert {:ok, []} = PriorityBiMap.put(bm, :a, 1, 5)
    assert {:ok, []} = PriorityBiMap.put(bm, :b, 2, 5)

    assert {:ok, 1} = PriorityBiMap.get_by_key(bm, :a)
    assert {:ok, 2} = PriorityBiMap.get_by_key(bm, :b)
  end

  # -------------------------------------------------------
  # Same-pair re-put updates priority
  # -------------------------------------------------------

  test "re-putting the same pair updates its priority and displaces nothing", %{bm: bm} do
    assert {:ok, []} = PriorityBiMap.put(bm, :x, 9, 3)
    assert {:ok, []} = PriorityBiMap.put(bm, :x, 9, 7)

    assert {:ok, 9} = PriorityBiMap.get_by_key(bm, :x)
    assert {:ok, 7} = PriorityBiMap.priority(bm, :x)
  end

  # -------------------------------------------------------
  # Rejection on insufficient priority
  # -------------------------------------------------------

  test "lower-priority put across two pairs is rejected and changes nothing", %{bm: bm} do
    PriorityBiMap.put(bm, :a, 1, 10)
    PriorityBiMap.put(bm, :b, 2, 10)

    # :a wants value 2 (held by :b) — conflicts with (a,1,10) and (b,2,10).
    assert {:error, :rejected} = PriorityBiMap.put(bm, :a, 2, 5)

    # Nothing moved.
    assert {:ok, 1} = PriorityBiMap.get_by_key(bm, :a)
    assert {:ok, 2} = PriorityBiMap.get_by_key(bm, :b)
    assert {:ok, :a} = PriorityBiMap.get_by_value(bm, 1)
    assert {:ok, :b} = PriorityBiMap.get_by_value(bm, 2)
    assert {:ok, 10} = PriorityBiMap.priority(bm, :a)
  end

  test "equal priority is a tie and is rejected", %{bm: bm} do
    PriorityBiMap.put(bm, :m, 1, 5)

    # New key :n wants value 1 (held by :m at prio 5). Tie -> rejected.
    assert {:error, :rejected} = PriorityBiMap.put(bm, :n, 1, 5)

    assert {:ok, :m} = PriorityBiMap.get_by_value(bm, 1)
    assert :error = PriorityBiMap.get_by_key(bm, :n)
  end

  # -------------------------------------------------------
  # Acceptance with displacement
  # -------------------------------------------------------

  test "single value-side conflict is displaced when priority wins", %{bm: bm} do
    PriorityBiMap.put(bm, :p, 1, 10)

    # :q wants value 1 (held by :p). 20 > 10 -> accept, displace (p,1).
    assert {:ok, evicted} = PriorityBiMap.put(bm, :q, 1, 20)
    assert evicted == [{:p, 1}]

    assert :error = PriorityBiMap.get_by_key(bm, :p)
    assert {:ok, :q} = PriorityBiMap.get_by_value(bm, 1)
    assert {:ok, 1} = PriorityBiMap.get_by_key(bm, :q)
    assert {:ok, 20} = PriorityBiMap.priority(bm, :q)
  end

  test "double conflict displaces both pairs when priority wins", %{bm: bm} do
    PriorityBiMap.put(bm, :a, 1, 10)
    PriorityBiMap.put(bm, :b, 2, 10)

    # :a wants value 2. Conflicts: (a,1,10) key-side and (b,2,10) value-side.
    assert {:ok, evicted} = PriorityBiMap.put(bm, :a, 2, 15)
    assert Enum.sort(evicted) == Enum.sort([{:a, 1}, {:b, 2}])

    # Surviving pair is consistent both ways.
    assert {:ok, 2} = PriorityBiMap.get_by_key(bm, :a)
    assert {:ok, :a} = PriorityBiMap.get_by_value(bm, 2)
    # Both old associations are gone.
    assert :error = PriorityBiMap.get_by_value(bm, 1)
    assert :error = PriorityBiMap.get_by_key(bm, :b)
    assert {:ok, 15} = PriorityBiMap.priority(bm, :a)
  end

  # -------------------------------------------------------
  # Delete and reuse
  # -------------------------------------------------------

  test "delete removes both directions and the priority", %{bm: bm} do
    PriorityBiMap.put(bm, :a, 1, 5)
    assert :ok = PriorityBiMap.delete(bm, :a)

    assert :error = PriorityBiMap.get_by_key(bm, :a)
    assert :error = PriorityBiMap.get_by_value(bm, 1)
    assert :error = PriorityBiMap.priority(bm, :a)
  end

  test "delete of an absent key is a harmless no-op", %{bm: bm} do
    assert :ok = PriorityBiMap.delete(bm, :ghost)
    PriorityBiMap.put(bm, :a, 1, 5)
    assert :ok = PriorityBiMap.delete(bm, :ghost)
    assert {:ok, 1} = PriorityBiMap.get_by_key(bm, :a)
  end

  test "a freed key/value can be re-used at any priority", %{bm: bm} do
    PriorityBiMap.put(bm, :a, 1, 10)
    PriorityBiMap.delete(bm, :a)

    # Value 1 is free again, so even a low priority installs cleanly.
    assert {:ok, []} = PriorityBiMap.put(bm, :b, 1, 1)
    assert {:ok, :b} = PriorityBiMap.get_by_value(bm, 1)
  end

  # -------------------------------------------------------
  # Bijection consistency across a mixed sequence
  # -------------------------------------------------------

  test "bijection holds across a mixed accept/reject sequence", %{bm: bm} do
    ops = [
      {:a, 1, 10},
      {:b, 2, 10},
      {:c, 3, 5},
      {:a, 2, 3},
      {:a, 2, 20},
      {:d, 3, 1},
      {:e, 3, 9},
      {:b, 1, 25}
    ]

    Enum.each(ops, fn {k, v, p} -> PriorityBiMap.put(bm, k, v, p) end)

    keys = [:a, :b, :c, :d, :e]
    values = [1, 2, 3]

    for k <- keys do
      case PriorityBiMap.get_by_key(bm, k) do
        {:ok, v} -> assert {:ok, ^k} = PriorityBiMap.get_by_value(bm, v)
        :error -> :ok
      end
    end

    for v <- values do
      case PriorityBiMap.get_by_value(bm, v) do
        {:ok, k} -> assert {:ok, ^v} = PriorityBiMap.get_by_key(bm, k)
        :error -> :ok
      end
    end
  end

  test "put beating one conflict but tying the other is rejected with no partial eviction", %{
    bm: bm
  } do
    PriorityBiMap.put(bm, :a, 1, 10)
    PriorityBiMap.put(bm, :b, 2, 7)

    # :a wants value 2. Conflicts: (a,1,10) key-side and (b,2,7) value-side.
    # 8 beats the value-side pair but not the key-side pair -> reject everything.
    assert {:error, :rejected} = PriorityBiMap.put(bm, :a, 2, 8)

    assert {:ok, 1} = PriorityBiMap.get_by_key(bm, :a)
    assert {:ok, :a} = PriorityBiMap.get_by_value(bm, 1)
    assert {:ok, 2} = PriorityBiMap.get_by_key(bm, :b)
    assert {:ok, :b} = PriorityBiMap.get_by_value(bm, 2)
    assert {:ok, 10} = PriorityBiMap.priority(bm, :a)
    assert {:ok, 7} = PriorityBiMap.priority(bm, :b)
  end

  test "rejected key-side-only conflict leaves the requested value entirely free", %{bm: bm} do
    PriorityBiMap.put(bm, :a, 1, 10)

    # Value 2 is free; the only conflict is the pair sitting at key :a.
    assert {:error, :rejected} = PriorityBiMap.put(bm, :a, 2, 4)

    assert {:ok, 1} = PriorityBiMap.get_by_key(bm, :a)
    assert {:ok, :a} = PriorityBiMap.get_by_value(bm, 1)
    assert {:ok, 10} = PriorityBiMap.priority(bm, :a)
    # No partial change: value 2 was never installed.
    assert :error = PriorityBiMap.get_by_value(bm, 2)
  end

  test "key-side-only conflict is displaced and frees its old value", %{bm: bm} do
    PriorityBiMap.put(bm, :a, 1, 10)

    # Value 2 is free; :a is rebound away from 1. 20 > 10 -> accept.
    assert {:ok, evicted} = PriorityBiMap.put(bm, :a, 2, 20)
    assert evicted == [{:a, 1}]

    assert {:ok, 2} = PriorityBiMap.get_by_key(bm, :a)
    assert {:ok, :a} = PriorityBiMap.get_by_value(bm, 2)
    assert {:ok, 20} = PriorityBiMap.priority(bm, :a)
    # The old value must not linger in the reverse direction.
    assert :error = PriorityBiMap.get_by_value(bm, 1)
  end

  test "re-putting the same pair at a lower priority lowers the stored priority", %{bm: bm} do
    assert {:ok, []} = PriorityBiMap.put(bm, :x, 9, 30)
    assert {:ok, []} = PriorityBiMap.put(bm, :x, 9, 2)

    assert {:ok, 9} = PriorityBiMap.get_by_key(bm, :x)
    assert {:ok, :x} = PriorityBiMap.get_by_value(bm, 9)
    assert {:ok, 2} = PriorityBiMap.priority(bm, :x)

    # The lowered priority really governs later conflicts.
    assert {:ok, [{:x, 9}]} = PriorityBiMap.put(bm, :y, 9, 3)
  end

  test "arbitrary terms work as keys and values in both directions", %{bm: bm} do
    key = {:tuple, [1, 2], %{nested: "map"}}
    value = %{"list" => [:a, {:b}], other: <<1, 2, 3>>}

    assert {:ok, []} = PriorityBiMap.put(bm, key, value, -5)
    assert {:ok, ^value} = PriorityBiMap.get_by_key(bm, key)
    assert {:ok, ^key} = PriorityBiMap.get_by_value(bm, value)
    assert {:ok, -5} = PriorityBiMap.priority(bm, key)

    assert {:ok, [{^key, ^value}]} = PriorityBiMap.put(bm, "str", value, -4)
    assert :error = PriorityBiMap.get_by_key(bm, key)
    assert {:ok, "str"} = PriorityBiMap.get_by_value(bm, value)
  end
end
