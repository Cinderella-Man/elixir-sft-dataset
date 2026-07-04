defmodule WorkStealQueueTest do
  use ExUnit.Case, async: false

  # -------------------------------------------------------
  # Helpers
  # -------------------------------------------------------

  defp processed_items(results), do: Enum.map(results, & &1.item)

  # -------------------------------------------------------
  # Result shape and completeness
  # -------------------------------------------------------

  test "returns a map with results and metrics; all items processed once" do
    items = Enum.to_list(1..20)
    %{results: results, metrics: metrics} = WorkStealQueue.run(items, 4, fn x -> x * 2 end)

    assert length(results) == 20
    assert Enum.sort(processed_items(results)) == Enum.sort(items)
    assert length(Enum.uniq_by(results, & &1.item)) == 20

    # metrics keys cover every worker id
    assert Map.keys(metrics.processed) |> Enum.sort() == [0, 1, 2, 3]
    assert Map.keys(metrics.steals) |> Enum.sort() == [0, 1, 2, 3]
    assert Map.keys(metrics.stolen) |> Enum.sort() == [0, 1, 2, 3]
  end

  test "results carry correct computed values" do
    items = Enum.to_list(1..10)
    %{results: results} = WorkStealQueue.run(items, 2, fn x -> x * x end)

    for %{item: item, result: result} <- results do
      assert result == item * item
    end
  end

  # -------------------------------------------------------
  # Metrics consistency
  # -------------------------------------------------------

  test "processed metric matches actual result distribution and totals" do
    items = Enum.to_list(1..40)
    %{results: results, metrics: metrics} = WorkStealQueue.run(items, 4, fn x -> x end)

    total_processed = metrics.processed |> Map.values() |> Enum.sum()
    assert total_processed == 40

    counts =
      results
      |> Enum.group_by(& &1.worker_id)
      |> Map.new(fn {wid, rs} -> {wid, length(rs)} end)

    for wid <- 0..3 do
      assert metrics.processed[wid] == Map.get(counts, wid, 0)
    end
  end

  test "single worker performs no steals" do
    items = Enum.to_list(1..10)
    %{metrics: metrics} = WorkStealQueue.run(items, 1, fn x -> x + 1 end)

    assert metrics.steals == %{0 => 0}
    assert metrics.stolen == %{0 => 0}
    assert metrics.processed == %{0 => 10}
  end

  # -------------------------------------------------------
  # Stealing actually happens and is measured
  # -------------------------------------------------------

  test "imbalanced load produces measurable steals" do
    slow_items = Enum.to_list(1..5)
    fast_items = Enum.to_list(6..25)
    items = slow_items ++ fast_items

    %{results: results, metrics: metrics} =
      WorkStealQueue.run(items, 4, fn x ->
        if x <= 5, do: Process.sleep(50)
        x
      end)

    assert length(results) == length(items)
    assert Enum.sort(processed_items(results)) == Enum.sort(items)

    total_steals = metrics.steals |> Map.values() |> Enum.sum()
    total_stolen = metrics.stolen |> Map.values() |> Enum.sum()

    assert total_steals > 0, "Expected at least one steal, got: #{inspect(metrics.steals)}"
    assert total_stolen >= total_steals
  end

  test "steal_batch: 1 still completes all work" do
    items = Enum.to_list(1..30)

    %{results: results, metrics: metrics} =
      WorkStealQueue.run(
        items,
        4,
        fn x ->
          if x <= 4, do: Process.sleep(30)
          x
        end,
        steal_batch: 1
      )

    assert length(results) == 30
    assert Enum.sort(processed_items(results)) == Enum.sort(items)

    total_processed = metrics.processed |> Map.values() |> Enum.sum()
    assert total_processed == 30
  end

  # -------------------------------------------------------
  # Edge cases
  # -------------------------------------------------------

  test "empty item list returns empty results and zeroed metrics" do
    %{results: results, metrics: metrics} = WorkStealQueue.run([], 3, fn x -> x end)

    assert results == []
    assert metrics.processed == %{0 => 0, 1 => 0, 2 => 0}
    assert metrics.steals == %{0 => 0, 1 => 0, 2 => 0}
    assert metrics.stolen == %{0 => 0, 1 => 0, 2 => 0}
  end

  test "worker_count greater than item count still processes everything" do
    items = [1, 2, 3]
    %{results: results, metrics: metrics} = WorkStealQueue.run(items, 10, fn x -> x end)

    assert length(results) == 3
    assert Enum.sort(processed_items(results)) == [1, 2, 3]
    assert Map.keys(metrics.processed) |> Enum.sort() == Enum.to_list(0..9)
  end

  test "single item is processed correctly" do
    %{results: results} = WorkStealQueue.run([:hello], 3, fn _ -> :world end)
    assert [%{item: :hello, result: :world, worker_id: wid}] = results
    assert wid >= 0 and wid < 3
  end

  test "worker_ids are within bounds" do
    %{results: results} = WorkStealQueue.run(Enum.to_list(1..30), 5, fn x -> x end)

    for %{worker_id: wid} <- results do
      assert wid >= 0 and wid < 5
    end
  end
end