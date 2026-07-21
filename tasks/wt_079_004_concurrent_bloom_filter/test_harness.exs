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
  # add/2 return value
  # -------------------------------------------------------

  test "add/2 returns the unchanged filter handle" do
    filter = ConcurrentBloomFilter.new(100, 0.01)

    # The documented return value is the same (unchanged) handle that was passed
    # in — not :ok and not a freshly built struct.
    assert ConcurrentBloomFilter.add(filter, "handle-back") == filter

    # Because the handle comes back unchanged, adds chain and every item added
    # through the chain is still a member of the original handle.
    returned =
      filter
      |> ConcurrentBloomFilter.add(:chained_one)
      |> ConcurrentBloomFilter.add({:chained, 2})

    assert returned == filter
    assert ConcurrentBloomFilter.member?(filter, :chained_one)
    assert ConcurrentBloomFilter.member?(filter, {:chained, 2})
  end

  test "add/2 in another process returns a handle usable back in the caller" do
    filter = ConcurrentBloomFilter.new(100, 0.01)

    returned =
      Task.async(fn -> ConcurrentBloomFilter.add(filter, "returned-from-task") end)
      |> Task.await()

    # The handle travelled back across processes unchanged and still reads the
    # same shared array.
    assert returned == filter
    assert ConcurrentBloomFilter.member?(returned, "returned-from-task")

    ConcurrentBloomFilter.add(returned, "added-via-returned-handle")
    assert ConcurrentBloomFilter.member?(filter, "added-via-returned-handle")
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
end
