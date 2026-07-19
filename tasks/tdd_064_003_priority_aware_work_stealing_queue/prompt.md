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

  defp payloads(results), do: Enum.map(results, & &1.item)

  # -------------------------------------------------------
  # Completeness
  # -------------------------------------------------------

  test "all payloads are returned exactly once" do
    items = for p <- 1..20, do: {p, p * 100}
    results = WorkStealQueue.run(items, 4, fn payload -> payload + 1 end)

    assert length(results) == 20
    expected_payloads = Enum.map(items, fn {_p, payload} -> payload end)
    assert Enum.sort(payloads(results)) == Enum.sort(expected_payloads)
    assert length(Enum.uniq_by(results, & &1.item)) == 20
  end

  test "results carry the correct computed value and priority" do
    items = [{5, 5}, {1, 1}, {3, 3}, {2, 2}, {4, 4}]
    results = WorkStealQueue.run(items, 2, fn payload -> payload * payload end)

    by_payload = Map.new(results, fn r -> {r.item, r} end)

    for {priority, payload} <- items do
      r = by_payload[payload]
      assert r.result == payload * payload
      assert r.priority == priority
    end
  end

  # -------------------------------------------------------
  # Priority ordering within a worker
  # -------------------------------------------------------

  test "a single worker processes items in strictly descending priority order" do
    {:ok, recorder} = Agent.start_link(fn -> [] end)

    # payload == priority; shuffled input
    items = [{3, 3}, {1, 1}, {5, 5}, {2, 2}, {4, 4}, {7, 7}, {6, 6}]

    WorkStealQueue.run(items, 1, fn payload ->
      Agent.update(recorder, fn acc -> [payload | acc] end)
      payload
    end)

    processing_order = recorder |> Agent.get(& &1) |> Enum.reverse()
    Agent.stop(recorder)

    assert processing_order == [7, 6, 5, 4, 3, 2, 1]
  end

  # -------------------------------------------------------
  # Stealing takes the low-priority work
  # -------------------------------------------------------

  test "idle workers steal low-priority items; owners keep their most urgent work" do
    # Partition of 8 items across 2 workers:
    #   worker 0 gets the first 4 (priorities 8,7,6,5 -> all slow)
    #   worker 1 gets the last 4  (priorities 4,3,2,1 -> all fast)
    # Worker 1 races through its fast items, then steals the LOW-priority
    # remainder of worker 0. Worker 0 always processes its top item (8) first.
    items = [{8, 8}, {7, 7}, {6, 6}, {5, 5}, {4, 4}, {3, 3}, {2, 2}, {1, 1}]

    results =
      WorkStealQueue.run(items, 2, fn payload ->
        if payload >= 5, do: Process.sleep(40)
        payload
      end)

    assert length(results) == 8

    worker_by_priority = Map.new(results, fn r -> {r.priority, r.worker_id} end)

    # The most urgent item is retained and processed by its owner (worker 0).
    assert worker_by_priority[8] == 0

    # At least one of worker 0's lower-priority items was stolen by worker 1.
    assert Enum.any?([5, 6, 7], fn p -> worker_by_priority[p] == 1 end),
           "Expected a low-priority item to be stolen, got: #{inspect(worker_by_priority)}"
  end

  # -------------------------------------------------------
  # Worker IDs / edge cases
  # -------------------------------------------------------

  test "worker_ids are within bounds" do
    items = for p <- 1..30, do: {p, p}
    results = WorkStealQueue.run(items, 5, fn payload -> payload end)

    for %{worker_id: wid} <- results do
      assert wid >= 0 and wid < 5
    end
  end

  test "worker_count greater than item count still processes everything" do
    items = [{1, :a}, {2, :b}, {3, :c}]
    results = WorkStealQueue.run(items, 10, fn payload -> payload end)

    assert length(results) == 3
    assert Enum.sort(payloads(results)) == [:a, :b, :c]
  end

  test "empty item list returns empty results" do
    results = WorkStealQueue.run([], 4, fn payload -> payload end)
    assert results == []
  end

  test "single item is processed correctly" do
    assert [%{item: :job, priority: 9, result: :done, worker_id: wid}] =
             WorkStealQueue.run([{9, :job}], 3, fn _ -> :done end)

    assert wid >= 0 and wid < 3
  end

  test "duplicate priorities are all processed exactly once" do
    items = for p <- [5, 5, 5, 3, 3, 1], do: {p, make_ref()}
    refs = Enum.map(items, fn {_p, ref} -> ref end)

    results = WorkStealQueue.run(items, 3, fn payload -> payload end)

    assert length(results) == 6
    assert Enum.sort(payloads(results)) == Enum.sort(refs)
  end
end
```

Give me the complete implementation in a single file — the module(s)
alone, not the tests.
