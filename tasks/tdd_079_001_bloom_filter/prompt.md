# Make this test suite pass

Below is a complete, self-contained ExUnit test suite. Treat it as the
full specification: write the module (or modules) under test so that
every test passes. Use only what the tests themselves require — the
standard library and OTP unless the suite references anything else.
Follow idiomatic Elixir house style (`@moduledoc`, `@doc` + `@spec` on
the public API, no compiler warnings).

## The test suite

```elixir
defmodule BloomFilterTest do
  use ExUnit.Case, async: true

  # -------------------------------------------------------
  # Construction
  # -------------------------------------------------------

  test "new/2 produces a struct with computed m and k" do
    filter = BloomFilter.new(1_000, 0.01)

    # Optimal m for n=1000, p=0.01 is ~9585 bits; k is ~7
    assert filter.m > 0
    assert filter.k > 0

    # Sanity: tighter false-positive rate → larger bit array
    loose = BloomFilter.new(1_000, 0.10)
    tight = BloomFilter.new(1_000, 0.01)
    assert tight.m > loose.m
  end

  test "new/2 with different expected sizes scales m accordingly" do
    small = BloomFilter.new(100, 0.01)
    large = BloomFilter.new(10_000, 0.01)
    assert large.m > small.m
  end

  # -------------------------------------------------------
  # No false negatives
  # -------------------------------------------------------

  test "member?/2 always returns true for added items (no false negatives)" do
    filter = BloomFilter.new(500, 0.01)

    items = for i <- 1..500, do: "item-#{i}"
    filter = Enum.reduce(items, filter, &BloomFilter.add(&2, &1))

    for item <- items do
      assert BloomFilter.member?(filter, item),
             "Expected #{inspect(item)} to be a member but got false"
    end
  end

  test "atoms, integers, and tuples are never false-negatives" do
    filter = BloomFilter.new(50, 0.01)
    items = [:alpha, :beta, 42, 0, {1, 2}, {"hello", :world}]
    filter = Enum.reduce(items, filter, &BloomFilter.add(&2, &1))

    for item <- items do
      assert BloomFilter.member?(filter, item)
    end
  end

  # -------------------------------------------------------
  # False positive rate
  # -------------------------------------------------------

  test "false positive rate stays near the configured value" do
    n = 1_000
    p = 0.03
    filter = BloomFilter.new(n, p)

    # Add n distinct items
    filter =
      Enum.reduce(1..n, filter, fn i, f ->
        BloomFilter.add(f, "present-#{i}")
      end)

    # Test n absent items and count false positives
    false_positives =
      Enum.count(1..n, fn i ->
        BloomFilter.member?(filter, "absent-#{i}")
      end)

    observed_rate = false_positives / n

    # Allow 2× headroom around the configured rate
    assert observed_rate < p * 2,
           "False positive rate #{observed_rate} exceeded 2× target #{p}"
  end

  # -------------------------------------------------------
  # Empty filter
  # -------------------------------------------------------

  test "empty filter reports no members" do
    filter = BloomFilter.new(100, 0.01)

    refute BloomFilter.member?(filter, "ghost")
    refute BloomFilter.member?(filter, 0)
    refute BloomFilter.member?(filter, :nope)
  end

  # -------------------------------------------------------
  # Merge
  # -------------------------------------------------------

  test "merge/2 contains all items from both filters" do
    f1 = BloomFilter.new(200, 0.01)
    f2 = BloomFilter.new(200, 0.01)

    f1 = Enum.reduce(1..100, f1, fn i, f -> BloomFilter.add(f, "a-#{i}") end)
    f2 = Enum.reduce(1..100, f2, fn i, f -> BloomFilter.add(f, "b-#{i}") end)

    merged = BloomFilter.merge(f1, f2)

    for i <- 1..100 do
      assert BloomFilter.member?(merged, "a-#{i}")
      assert BloomFilter.member?(merged, "b-#{i}")
    end
  end

  test "merge/2 raises ArgumentError when filters have different parameters" do
    f1 = BloomFilter.new(100, 0.01)
    f2 = BloomFilter.new(999, 0.05)

    assert_raise ArgumentError, fn ->
      BloomFilter.merge(f1, f2)
    end
  end

  test "merge/2 with an empty filter leaves the other unchanged" do
    f1 = BloomFilter.new(100, 0.01)
    empty = BloomFilter.new(100, 0.01)

    f1 = Enum.reduce(["x", "y", "z"], f1, &BloomFilter.add(&2, &1))
    merged = BloomFilter.merge(f1, empty)

    assert BloomFilter.member?(merged, "x")
    assert BloomFilter.member?(merged, "y")
    assert BloomFilter.member?(merged, "z")
  end

  test "merge/2 is commutative" do
    f1 = BloomFilter.new(100, 0.01)
    f2 = BloomFilter.new(100, 0.01)

    f1 = BloomFilter.add(f1, "only-in-f1")
    f2 = BloomFilter.add(f2, "only-in-f2")

    m1 = BloomFilter.merge(f1, f2)
    m2 = BloomFilter.merge(f2, f1)

    assert BloomFilter.member?(m1, "only-in-f1")
    assert BloomFilter.member?(m1, "only-in-f2")
    assert BloomFilter.member?(m2, "only-in-f1")
    assert BloomFilter.member?(m2, "only-in-f2")

    # Bit arrays should be identical
    assert m1.bits == m2.bits
  end

  # -------------------------------------------------------
  # Idempotency
  # -------------------------------------------------------

  test "adding the same item multiple times has no extra effect" do
    f = BloomFilter.new(10, 0.01)
    f1 = BloomFilter.add(f, "dup")
    f2 = BloomFilter.add(f1, "dup")

    assert f1.bits == f2.bits
    assert BloomFilter.member?(f2, "dup")
  end

  # -------------------------------------------------------
  # Guard boundaries on new/2 (documented: exclusive ranges)
  # -------------------------------------------------------

  test "new/2 rejects sizes <= 0 and rates outside (0.0, 1.0) with FunctionClauseError" do
    assert_raise FunctionClauseError, fn -> BloomFilter.new(0, 0.01) end
    assert_raise FunctionClauseError, fn -> BloomFilter.new(-5, 0.01) end
    assert_raise FunctionClauseError, fn -> BloomFilter.new(100, 0.0) end
    assert_raise FunctionClauseError, fn -> BloomFilter.new(100, 1.0) end
    assert_raise FunctionClauseError, fn -> BloomFilter.new(100, 1) end
  end

  test "new/2 accepts the smallest positive expected size (n = 1)" do
    filter = BloomFilter.new(1, 0.5)

    assert %BloomFilter{} = filter
    assert filter.m >= 1
    assert filter.k >= 1
    assert BloomFilter.member?(BloomFilter.add(filter, :only), :only)
  end

  # -------------------------------------------------------
  # Documented parameter derivation and bit-array shape
  # -------------------------------------------------------

  test "new/2 derives the documented m, k, word count and all-zero words" do
    filter = BloomFilter.new(1_000, 0.01)

    assert filter.m == 9586
    assert filter.k == 7
    # ceil(m / 64) 64-bit words
    assert tuple_size(filter.bits) == 150
    assert Enum.all?(Tuple.to_list(filter.bits), &(&1 == 0))
  end

  test "new/2 floors k at 1 for a very loose false-positive rate" do
    filter = BloomFilter.new(1_000, 0.9)

    assert filter.m == 220
    assert filter.k == 1
    assert Enum.all?(Tuple.to_list(filter.bits), &(&1 == 0))
    refute BloomFilter.member?(filter, "ghost")
  end

  # -------------------------------------------------------
  # Exact hashing / bit layout
  # -------------------------------------------------------

  test "add/2 sets exactly the bits phash2({i, item}, m) for i in 0..k-1" do
    filter = BloomFilter.new(1_000, 0.01)

    for item <- ["probe-a", :probe_b, 12_345, {:probe, "c"}, [1, 2, 3]] do
      added = BloomFilter.add(filter, item)
      expected = MapSet.new(hash_indices(filter, item))

      assert set_bit_indices(added.bits) == expected
      assert tuple_size(added.bits) == tuple_size(filter.bits)
      assert added.m == filter.m
      assert added.k == filter.k
    end
  end

  test "member?/2 needs every one of the k bits, first and last seed included" do
    filter = BloomFilter.new(1_000, 0.01)

    # Pick a probe whose k bit indices are all distinct, so that dropping any
    # single one of them really leaves that bit unset.
    item =
      Enum.find(Enum.map(0..99, &"seed-probe-#{&1}"), fn candidate ->
        indices = hash_indices(filter, candidate)
        length(Enum.uniq(indices)) == filter.k
      end)

    assert item
    indices = hash_indices(filter, item)

    full = %BloomFilter{filter | bits: bits_from_indices(indices, filter.m)}
    assert BloomFilter.member?(full, item)

    for dropped <- [List.first(indices), List.last(indices)] do
      remaining = indices -- [dropped]
      partial = %BloomFilter{filter | bits: bits_from_indices(remaining, filter.m)}

      refute BloomFilter.member?(partial, item)
    end
  end

  # -------------------------------------------------------
  # Helpers (mirror the documented hashing and bit layout)
  # -------------------------------------------------------

  defp hash_indices(%BloomFilter{k: k, m: m}, item) do
    for i <- 0..(k - 1), do: :erlang.phash2({i, item}, m)
  end

  defp bits_from_indices(indices, m) do
    empty = Tuple.duplicate(0, ceil(m / 64))

    Enum.reduce(indices, empty, fn index, acc ->
      wi = div(index, 64)
      word = Bitwise.bor(elem(acc, wi), Bitwise.bsl(1, rem(index, 64)))
      put_elem(acc, wi, word)
    end)
  end

  defp set_bit_indices(bits) do
    bits
    |> Tuple.to_list()
    |> Enum.with_index()
    |> Enum.flat_map(fn {word, wi} ->
      for bo <- 0..63, Bitwise.band(Bitwise.bsr(word, bo), 1) == 1, do: wi * 64 + bo
    end)
    |> MapSet.new()
  end

  test "merge/2 raises FunctionClauseError when an argument is not a filter struct" do
    f = BloomFilter.new(100, 0.01)
    look_alike = %{m: f.m, k: f.k, bits: f.bits}

    assert_raise FunctionClauseError, fn -> BloomFilter.merge(f, look_alike) end
    assert_raise FunctionClauseError, fn -> BloomFilter.merge(look_alike, f) end
    assert_raise FunctionClauseError, fn -> BloomFilter.merge(nil, f) end
    assert_raise FunctionClauseError, fn -> BloomFilter.merge(f, :not_a_filter) end
  end

  test "merge/2 error message names both filters' m and k values" do
    f1 = BloomFilter.new(100, 0.01)
    f2 = BloomFilter.new(999, 0.05)

    error = assert_raise ArgumentError, fn -> BloomFilter.merge(f1, f2) end

    assert error.message =~ "cannot merge filters with different parameters"
    assert error.message =~ "filter1 has m=#{f1.m}, k=#{f1.k}"
    assert error.message =~ "filter2 has m=#{f2.m}, k=#{f2.k}"
  end

  test "merge/2 is associative and idempotent on identical inputs" do
    a = BloomFilter.new(100, 0.01) |> BloomFilter.add("a-item")
    b = BloomFilter.new(100, 0.01) |> BloomFilter.add("b-item")
    c = BloomFilter.new(100, 0.01) |> BloomFilter.add({:c, 3})

    left = BloomFilter.merge(BloomFilter.merge(a, b), c)
    right = BloomFilter.merge(a, BloomFilter.merge(b, c))

    assert left == right
    assert BloomFilter.merge(a, a) == a
    assert BloomFilter.merge(left, left) == left
    assert BloomFilter.member?(left, "a-item")
    assert BloomFilter.member?(left, "b-item")
    assert BloomFilter.member?(left, {:c, 3})
  end

  test "add/2 yields equal structs regardless of insertion order" do
    empty = BloomFilter.new(100, 0.01)
    items = ["x", :y, 3, {4, "z"}, [5, 6]]

    build = fn list -> Enum.reduce(list, empty, &BloomFilter.add(&2, &1)) end

    forward = build.(items)
    backward = build.(Enum.reverse(items))
    rotated = build.(tl(items) ++ [hd(items)])

    assert forward == backward
    assert forward == rotated
    assert forward.bits == rotated.bits
  end

  test "add/2 preserves every previously set bit as items accumulate" do
    start = BloomFilter.new(200, 0.01)

    Enum.reduce(1..50, start, fn i, f ->
      next = BloomFilter.add(f, {:grow, i})

      assert tuple_size(next.bits) == tuple_size(f.bits)

      for wi <- 0..(tuple_size(f.bits) - 1) do
        old_word = elem(f.bits, wi)
        assert Bitwise.band(old_word, elem(next.bits, wi)) == old_word
      end

      assert BloomFilter.member?(next, {:grow, i})
      next
    end)
  end

  test "new/2 returns equal structs for repeated calls with identical arguments" do
    assert BloomFilter.new(1_000, 0.01) == BloomFilter.new(1_000, 0.01)
    assert BloomFilter.new(7, 0.25) == BloomFilter.new(7, 0.25)
    assert BloomFilter.new(1_000, 0.9) == BloomFilter.new(1_000, 0.9)
  end
end
```

Give me the complete implementation in a single file — the module(s)
alone, not the tests.
