# Make this test suite pass

Below is a complete, self-contained ExUnit test suite. Treat it as the
full specification: write the module (or modules) under test so that
every test passes. Use only what the tests themselves require — the
standard library and OTP unless the suite references anything else.
Follow idiomatic Elixir house style (`@moduledoc`, `@doc` + `@spec` on
the public API, no compiler warnings).

## The test suite

```elixir
defmodule WorkStealQueueTest do
  use ExUnit.Case, async: false

  # -------------------------------------------------------
  # Helpers
  # -------------------------------------------------------

  # Returns the set of worker_ids that actually processed items
  defp worker_ids(results), do: results |> Enum.map(& &1.worker_id) |> Enum.uniq()

  # Extracts processed items (unordered)
  defp processed_items(results), do: Enum.map(results, & &1.item)

  # -------------------------------------------------------
  # Completeness
  # -------------------------------------------------------

  test "all items are returned" do
    items = Enum.to_list(1..20)
    results = WorkStealQueue.run(items, 4, fn x -> x * 2 end)

    assert length(results) == 20
    assert Enum.sort(processed_items(results)) == Enum.sort(items)
  end

  test "results contain correct computed values" do
    items = Enum.to_list(1..10)
    results = WorkStealQueue.run(items, 2, fn x -> x * x end)

    for %{item: item, result: result} <- results do
      assert result == item * item
    end
  end

  # -------------------------------------------------------
  # Worker IDs
  # -------------------------------------------------------

  test "worker_ids are within bounds" do
    results = WorkStealQueue.run(Enum.to_list(1..30), 5, fn x -> x end)

    for %{worker_id: wid} <- results do
      assert wid >= 0 and wid < 5
    end
  end

  test "with more items than workers, all workers are used" do
    results = WorkStealQueue.run(Enum.to_list(1..50), 4, fn x -> x end)

    # With 50 items split across 4 workers, every worker should get at
    # least some items before stealing even begins.
    assert length(worker_ids(results)) == 4
  end

  test "worker_count greater than item count still processes everything" do
    items = [1, 2, 3]
    results = WorkStealQueue.run(items, 10, fn x -> x end)

    assert length(results) == 3
    assert Enum.sort(processed_items(results)) == [1, 2, 3]
  end

  # -------------------------------------------------------
  # Work stealing actually happens
  # -------------------------------------------------------

  test "fast workers process more items than slow ones (stealing occurred)" do
    # Items 1–5 are slow, items 6–25 are fast.
    # Worker 0 gets the slow items; faster workers should steal from each other
    # and collectively outpace worker 0.
    slow_items = Enum.to_list(1..5)
    fast_items = Enum.to_list(6..25)
    items = slow_items ++ fast_items

    results =
      WorkStealQueue.run(items, 4, fn x ->
        if x <= 5 do
          # slow
          Process.sleep(50)
          x
        else
          # fast (no sleep)
          x
        end
      end)

    # All items processed
    assert length(results) == length(items)
    assert Enum.sort(processed_items(results)) == Enum.sort(items)

    # Count items per worker
    counts_by_worker =
      results
      |> Enum.group_by(& &1.worker_id)
      |> Map.new(fn {wid, rs} -> {wid, length(rs)} end)

    # The worker that handled slow items processed at most 5 items in the
    # time others processed many more. At least one other worker should
    # have processed more items than the slowest worker did.
    min_count = counts_by_worker |> Map.values() |> Enum.min()
    max_count = counts_by_worker |> Map.values() |> Enum.max()

    assert max_count > min_count,
           "Expected work stealing to cause unequal distribution, got: #{inspect(counts_by_worker)}"
  end

  test "a worker processes more items than any initial queue could hold" do
    # 100 items across 4 workers partitions "as evenly as possible" into
    # local queues of exactly 25 items each — so 25 is the largest queue any
    # worker can own before stealing. The worker holding the first item is
    # blocked long enough that the other three drain their own queues and must
    # steal from it. If any worker finishes with more than 25 items, those
    # extra items can only have arrived by stealing from another worker.
    worker_count = 4
    items = Enum.to_list(0..99)
    initial_max = div(length(items) + worker_count - 1, worker_count)

    results =
      WorkStealQueue.run(items, worker_count, fn x ->
        if x == 0, do: Process.sleep(150)
        x
      end)

    assert length(results) == length(items)
    assert Enum.sort(processed_items(results)) == Enum.sort(items)

    max_count =
      results
      |> Enum.group_by(& &1.worker_id)
      |> Map.values()
      |> Enum.map(&length/1)
      |> Enum.max()

    assert max_count > initial_max,
           "one worker processed #{max_count} items but no initial queue held " <>
             "more than #{initial_max}; the surplus can only come from stealing"
  end

  test "single worker processes all items without stealing" do
    items = Enum.to_list(1..10)
    results = WorkStealQueue.run(items, 1, fn x -> x + 1 end)

    assert length(results) == 10
    assert Enum.map(results, & &1.worker_id) |> Enum.uniq() == [0]
    assert Enum.sort(processed_items(results)) == items
  end

  # -------------------------------------------------------
  # Edge cases
  # -------------------------------------------------------

  test "empty item list returns empty results" do
    results = WorkStealQueue.run([], 4, fn x -> x end)
    assert results == []
  end

  test "single item is processed correctly" do
    assert [%{item: :hello, result: :world, worker_id: wid}] =
             WorkStealQueue.run([:hello], 3, fn _ -> :world end)

    assert wid >= 0 and wid < 3
  end

  test "process_fn returning complex terms works" do
    items = [:a, :b, :c]
    results = WorkStealQueue.run(items, 2, fn x -> {x, to_string(x)} end)

    assert length(results) == 3

    for %{item: item, result: result} <- results do
      assert result == {item, to_string(item)}
    end
  end

  test "no duplicate processing — each item processed exactly once" do
    items = Enum.to_list(1..40)
    results = WorkStealQueue.run(items, 4, fn x -> x end)

    assert length(results) == 40
    assert length(Enum.uniq_by(results, & &1.item)) == 40
  end
end
```

Give me the complete implementation in a single file — the module(s)
alone, not the tests.
