defmodule ConcurrentBloomFilterTest do
  use ExUnit.Case, async: false

  # -------------------------------------------------------
  # Construction
  # -------------------------------------------------------

  test "new/2 computes m and k and allocates an atomics-backed filter" do
    filter = ConcurrentBloomFilter.new(1_000, 0.01)
    assert filter.m > 0
    assert filter.k > 0

    loose = ConcurrentBloomFilter.new(1_000, 0.10)
    tight = ConcurrentBloomFilter.new(1_000, 0.01)
    assert tight.m > loose.m
  end

  # -------------------------------------------------------
  # Shared mutable semantics
  # -------------------------------------------------------

  test "adds are visible across processes sharing the handle" do
    filter = ConcurrentBloomFilter.new(100, 0.01)

    task =
      Task.async(fn ->
        ConcurrentBloomFilter.add(filter, "written-elsewhere")
      end)

    Task.await(task)

    # The mutation happened in another process but is visible here because the
    # backing :atomics array is shared.
    assert ConcurrentBloomFilter.member?(filter, "written-elsewhere")
  end

  # -------------------------------------------------------
  # No false negatives
  # -------------------------------------------------------

  test "member?/2 true for all added items (single process)" do
    filter = ConcurrentBloomFilter.new(500, 0.01)
    items = for i <- 1..500, do: "item-#{i}"
    Enum.each(items, fn item -> ConcurrentBloomFilter.add(filter, item) end)

    for item <- items do
      assert ConcurrentBloomFilter.member?(filter, item)
    end
  end

  test "mixed term types are never false-negatives" do
    filter = ConcurrentBloomFilter.new(50, 0.01)
    items = [:alpha, :beta, 42, 0, {1, 2}, {"hello", :world}]
    Enum.each(items, fn item -> ConcurrentBloomFilter.add(filter, item) end)

    for item <- items do
      assert ConcurrentBloomFilter.member?(filter, item)
    end
  end

  # -------------------------------------------------------
  # Concurrent writes
  # -------------------------------------------------------

  test "concurrent adds from many processes lose no items" do
    filter = ConcurrentBloomFilter.new(5_000, 0.01)
    items = for i <- 1..5_000, do: "concurrent-#{i}"

    items
    |> Task.async_stream(
      fn item -> ConcurrentBloomFilter.add(filter, item) end,
      max_concurrency: 16,
      ordered: false
    )
    |> Stream.run()

    for item <- items do
      assert ConcurrentBloomFilter.member?(filter, item),
             "Expected #{inspect(item)} to survive concurrent insertion"
    end
  end

  # -------------------------------------------------------
  # False positive rate
  # -------------------------------------------------------

  test "false positive rate stays near the configured value" do
    n = 1_000
    p = 0.03
    filter = ConcurrentBloomFilter.new(n, p)

    Enum.each(1..n, fn i -> ConcurrentBloomFilter.add(filter, "present-#{i}") end)

    false_positives =
      Enum.count(1..n, fn i -> ConcurrentBloomFilter.member?(filter, "absent-#{i}") end)

    observed = false_positives / n

    assert observed < p * 2,
           "False positive rate #{observed} exceeded 2x target #{p}"
  end

  # -------------------------------------------------------
  # Empty filter
  # -------------------------------------------------------

  test "empty filter reports no members" do
    filter = ConcurrentBloomFilter.new(100, 0.01)
    refute ConcurrentBloomFilter.member?(filter, "ghost")
    refute ConcurrentBloomFilter.member?(filter, 0)
    refute ConcurrentBloomFilter.member?(filter, :nope)
  end

  # -------------------------------------------------------
  # Merge
  # -------------------------------------------------------

  test "merge/2 ORs the source into the target in place" do
    into = ConcurrentBloomFilter.new(200, 0.01)
    from = ConcurrentBloomFilter.new(200, 0.01)

    Enum.each(1..100, fn i -> ConcurrentBloomFilter.add(into, "a-#{i}") end)
    Enum.each(1..100, fn i -> ConcurrentBloomFilter.add(from, "b-#{i}") end)

    result = ConcurrentBloomFilter.merge(into, from)

    for i <- 1..100 do
      assert ConcurrentBloomFilter.member?(result, "a-#{i}")
      assert ConcurrentBloomFilter.member?(result, "b-#{i}")
    end

    # `into` was mutated in place and now also contains from's items.
    assert ConcurrentBloomFilter.member?(into, "b-1")
  end

  test "merge/2 raises when parameters differ" do
    f1 = ConcurrentBloomFilter.new(100, 0.01)
    f2 = ConcurrentBloomFilter.new(999, 0.05)

    assert_raise ArgumentError, fn -> ConcurrentBloomFilter.merge(f1, f2) end
  end

  test "new/2 sizes m and k exactly by the documented formulas" do
    n = 1_000
    p = 0.01
    ln2 = :math.log(2)
    expected_m = -ceil(n * :math.log(p) / (ln2 * ln2))
    expected_k = round(expected_m / n * ln2)

    filter = ConcurrentBloomFilter.new(n, p)

    assert filter.m == expected_m
    assert filter.k == expected_k
  end

  test "new/2 allocates exactly m slots and they are unsigned" do
    filter = ConcurrentBloomFilter.new(1_000, 0.01)
    info = :atomics.info(filter.ref)

    assert info.size == filter.m
    assert info.min == 0
    assert info.max > 0
  end

  test "add/2 hands back the very same filter handle it was given" do
    filter = ConcurrentBloomFilter.new(100, 0.01)

    returned = ConcurrentBloomFilter.add(filter, "handle-check")

    assert returned == filter
    assert returned.ref == filter.ref
    assert returned.m == filter.m
    assert returned.k == filter.k
    assert ConcurrentBloomFilter.member?(returned, "handle-check")
  end

  test "merge/2 returns the into handle itself and does not disturb from" do
    into = ConcurrentBloomFilter.new(200, 0.01)
    from = ConcurrentBloomFilter.new(200, 0.01)

    ConcurrentBloomFilter.add(from, "only-in-from")

    result = ConcurrentBloomFilter.merge(into, from)

    assert result == into
    assert result.ref == into.ref
    assert ConcurrentBloomFilter.member?(from, "only-in-from")
    refute ConcurrentBloomFilter.member?(from, "never-added-anywhere")
  end

  test "add/2 and member?/2 handle maps, lists, floats, pids, refs and binaries" do
    filter = ConcurrentBloomFilter.new(50, 0.01)

    items = [
      %{a: 1, b: [2, 3]},
      [1, [2], {3}],
      3.14,
      self(),
      make_ref(),
      "",
      <<0, 255>>,
      nil,
      true
    ]

    Enum.each(items, fn item -> ConcurrentBloomFilter.add(filter, item) end)

    for item <- items do
      assert ConcurrentBloomFilter.member?(filter, item),
             "Expected #{inspect(item)} to be a member after add/2"
    end
  end
end
