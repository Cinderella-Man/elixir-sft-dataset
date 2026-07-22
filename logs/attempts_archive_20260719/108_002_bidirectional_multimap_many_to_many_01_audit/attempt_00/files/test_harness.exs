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
    BiMultiMap.put(bm, :a, 1)
    assert :ok = BiMultiMap.delete(bm, :a, 999)
    assert :ok = BiMultiMap.delete(bm, :ghost, 1)
    assert MapSet.new([1]) == BiMultiMap.get_by_key(bm, :a)
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

  test "arbitrary terms work as keys and values in both directions", %{bm: bm} do
    key = {:user, "abe", [1, 2]}
    value = %{tag: "v", list: [:x, {:y, 3}]}

    assert :ok = BiMultiMap.put(bm, key, value)
    assert :ok = BiMultiMap.put(bm, "string-key", value)
    assert :ok = BiMultiMap.put(bm, key, 3.5)

    assert BiMultiMap.member?(bm, key, value)
    assert MapSet.new([value, 3.5]) == BiMultiMap.get_by_key(bm, key)
    assert MapSet.new([key, "string-key"]) == BiMultiMap.get_by_value(bm, value)

    assert :ok = BiMultiMap.delete(bm, key, value)
    refute BiMultiMap.member?(bm, key, value)
    assert MapSet.new(["string-key"]) == BiMultiMap.get_by_value(bm, value)
    assert MapSet.new([3.5]) == BiMultiMap.get_by_key(bm, key)
  end
end
