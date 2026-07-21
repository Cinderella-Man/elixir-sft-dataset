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

  defp processed_items(results), do: Enum.map(results, & &1.item)
  defp worker_ids(results), do: results |> Enum.map(& &1.worker_id) |> Enum.uniq()

  # -------------------------------------------------------
  # Completeness
  # -------------------------------------------------------

  test "all items are returned exactly once" do
    items = Enum.to_list(1..20)
    results = WorkStealQueue.run(items, 4, fn x -> x * 2 end)

    assert length(results) == 20
    assert Enum.sort(processed_items(results)) == Enum.sort(items)
    assert length(Enum.uniq_by(results, & &1.item)) == 20
  end

  test "successful results are tagged {:ok, value}" do
    items = Enum.to_list(1..10)
    results = WorkStealQueue.run(items, 2, fn x -> x * x end)

    for %{item: item, result: result} <- results do
      assert result == {:ok, item * item}
    end
  end

  # -------------------------------------------------------
  # Fault tolerance / tagging
  # -------------------------------------------------------

  test "raised exceptions are captured and tagged, others still succeed" do
    items = Enum.to_list(1..10)

    results =
      WorkStealQueue.run(items, 3, fn x ->
        if rem(x, 2) == 0, do: raise("boom-#{x}"), else: x
      end)

    assert length(results) == 10

    by_item = Map.new(results, fn r -> {r.item, r.result} end)

    for x <- items do
      if rem(x, 2) == 0 do
        assert {:error, %{kind: :error, reason: reason}} = by_item[x]
        assert reason == "boom-#{x}"
      else
        assert by_item[x] == {:ok, x}
      end
    end
  end

  test "thrown values are captured and tagged with kind :throw" do
    items = [:a, :b, :c]
    results = WorkStealQueue.run(items, 2, fn x -> throw({:bad, x}) end)

    assert length(results) == 3

    for %{item: item, result: result} <- results do
      assert result == {:error, %{kind: :throw, reason: {:bad, item}}}
    end
  end

  test "exits are captured and tagged with kind :exit" do
    items = [1, 2, 3]
    results = WorkStealQueue.run(items, 2, fn x -> exit({:down, x}) end)

    assert length(results) == 3

    for %{item: item, result: result} <- results do
      assert result == {:error, %{kind: :exit, reason: {:down, item}}}
    end
  end

  test "a worker keeps processing its queue after a failing item" do
    # Every item in this worker's queue except one raises; all must be returned.
    items = Enum.to_list(1..12)

    results =
      WorkStealQueue.run(items, 1, fn x ->
        if x == 6, do: raise("only six fails"), else: x
      end)

    assert length(results) == 12
    by_item = Map.new(results, fn r -> {r.item, r.result} end)
    assert {:error, %{kind: :error}} = by_item[6]

    for x <- items, x != 6 do
      assert by_item[x] == {:ok, x}
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

  test "worker_count greater than item count still processes everything" do
    items = [1, 2, 3]
    results = WorkStealQueue.run(items, 10, fn x -> x end)

    assert length(results) == 3
    assert Enum.sort(processed_items(results)) == [1, 2, 3]
  end

  # -------------------------------------------------------
  # Work stealing happens even amidst failures
  # -------------------------------------------------------

  test "fast workers pick up slack, and errors do not break stealing" do
    slow_items = Enum.to_list(1..5)
    fast_items = Enum.to_list(6..25)
    items = slow_items ++ fast_items

    results =
      WorkStealQueue.run(items, 4, fn x ->
        cond do
          x <= 5 ->
            Process.sleep(50)
            x

          rem(x, 3) == 0 ->
            raise("fast-failure-#{x}")

          true ->
            x
        end
      end)

    assert length(results) == length(items)
    assert Enum.sort(processed_items(results)) == Enum.sort(items)

    counts_by_worker =
      results
      |> Enum.group_by(& &1.worker_id)
      |> Map.new(fn {wid, rs} -> {wid, length(rs)} end)

    min_count = counts_by_worker |> Map.values() |> Enum.min()
    max_count = counts_by_worker |> Map.values() |> Enum.max()

    assert max_count > min_count,
           "Expected work stealing to cause unequal distribution, got: #{inspect(counts_by_worker)}"
  end

  test "a thief steals the back half of a busy queue and leaves the front" do
    # Items partition contiguously into {1,2,3} for one worker and {4,5,6}
    # for the other. The 4..6 worker returns instantly, empties its queue,
    # and steals from the slow 1..3 worker. A steal takes the back half
    # rounded down and leaves the front half: item 3 is carried off by the
    # thief, while items 1 and 2 stay with and are processed by the original
    # owner. Once that owner is down to a single remaining item it is never
    # robbed, so item 2 always belongs to the owner, not the thief.
    items = Enum.to_list(1..6)

    results =
      WorkStealQueue.run(items, 2, fn x ->
        if x <= 3, do: Process.sleep(120)
        x
      end)

    assert length(results) == 6
    assert Enum.sort(processed_items(results)) == items

    for %{item: item, result: result} <- results do
      assert result == {:ok, item}
    end

    by_worker = Map.new(results, fn r -> {r.item, r.worker_id} end)

    # The fast worker processes its own partition {4,5,6}.
    assert by_worker[4] == by_worker[5]
    assert by_worker[5] == by_worker[6]

    # It then steals the back half of the slow queue, so item 3 moves to it.
    assert by_worker[3] == by_worker[6]

    # The slow worker keeps and processes the front half; item 2 is never
    # stolen because a one-item victim is left alone.
    assert by_worker[1] == by_worker[2]
    assert by_worker[1] != by_worker[6]
  end

  test "single worker processes all items without stealing" do
    items = Enum.to_list(1..10)
    results = WorkStealQueue.run(items, 1, fn x -> x + 1 end)

    assert length(results) == 10
    assert worker_ids(results) == [0]

    for %{item: item, result: result} <- results do
      assert result == {:ok, item + 1}
    end
  end

  # -------------------------------------------------------
  # Edge cases
  # -------------------------------------------------------

  test "empty item list returns empty results" do
    results = WorkStealQueue.run([], 4, fn x -> x end)
    assert results == []
  end

  test "single item is processed correctly" do
    assert [%{item: :hello, result: {:ok, :world}, worker_id: wid}] =
             WorkStealQueue.run([:hello], 3, fn _ -> :world end)

    assert wid >= 0 and wid < 3
  end

  test "process_fn is applied exactly once per item even when work is stolen" do
    parent = self()
    items = Enum.to_list(1..30)

    results =
      WorkStealQueue.run(items, 4, fn x ->
        send(parent, {:applied, x})
        x
      end)

    assert length(results) == 30

    seen =
      for _ <- 1..30 do
        assert_receive {:applied, x}, 1_000
        x
      end

    assert Enum.sort(seen) == items
    refute_receive {:applied, _}, 100
  end

  test "duplicate items each get their own result entry" do
    items = [:dup, :dup, :dup, :other, :dup]
    results = WorkStealQueue.run(items, 3, fn x -> x end)

    assert length(results) == 5
    assert Enum.count(results, &(&1.item == :dup)) == 4
    assert Enum.count(results, &(&1.item == :other)) == 1
    assert Enum.all?(results, fn r -> r.result == {:ok, r.item} end)
  end

  test "one item per worker means every worker_id appears exactly once" do
    items = Enum.to_list(1..6)
    results = WorkStealQueue.run(items, 6, fn x -> x end)

    assert length(results) == 6
    assert results |> Enum.map(& &1.worker_id) |> Enum.sort() == Enum.to_list(0..5)
  end

  test "an exit with reason :normal is still captured and tagged" do
    results = WorkStealQueue.run([1, 2], 2, fn _ -> exit(:normal) end)

    assert length(results) == 2

    for %{result: result} <- results do
      assert result == {:error, %{kind: :exit, reason: :normal}}
    end
  end

  test "idle workers give up when the only item fails and run/3 still returns" do
    results = WorkStealQueue.run([:boom_item], 8, fn _ -> raise "kaboom" end)

    assert [%{item: :boom_item, result: result, worker_id: wid}] = results
    assert result == {:error, %{kind: :error, reason: "kaboom"}}
    assert wid >= 0 and wid < 8
  end

  test "error-shaped and nil return values are still tagged as successes" do
    items = [:nil_item, :err_item, :exit_item]

    results =
      WorkStealQueue.run(items, 2, fn
        :nil_item -> nil
        :err_item -> {:error, %{kind: :error, reason: "not really raised"}}
        :exit_item -> {:exit, :boom}
      end)

    by_item = Map.new(results, fn r -> {r.item, r.result} end)

    assert by_item[:nil_item] == {:ok, nil}
    assert by_item[:err_item] == {:ok, {:error, %{kind: :error, reason: "not really raised"}}}
    assert by_item[:exit_item] == {:ok, {:exit, :boom}}
  end
end
```

Give me the complete implementation in a single file — the module(s)
alone, not the tests.
