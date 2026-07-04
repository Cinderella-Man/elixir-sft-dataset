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
end