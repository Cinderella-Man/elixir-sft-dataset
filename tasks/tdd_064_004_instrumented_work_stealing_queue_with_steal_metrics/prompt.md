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

  test "default steal batch takes half of the victim's remaining queue per steal" do
    test_pid = self()
    items = [:block, 1, 2, 3, 4, :gate, 5, 6, 7, 8]

    task =
      Task.async(fn ->
        WorkStealQueue.run(items, 2, fn
          :block ->
            send(test_pid, {:blocked, self()})

            receive do
              :release -> :released
            end

          :gate ->
            send(test_pid, {:gated, self()})

            receive do
              :go -> :went
            end

          x ->
            send(test_pid, {:processed, x})
            x
        end)
      end)

    # worker 0 owns [:block, 1, 2, 3, 4]; worker 1 owns [:gate, 5, 6, 7, 8].
    # Both park on their first item, so worker 0's remaining queue is [1, 2, 3, 4].
    assert_receive {:gated, gate_pid}, 2_000
    assert_receive {:blocked, block_pid}, 2_000
    send(gate_pid, :go)

    seq =
      for _ <- 1..8 do
        assert_receive {:processed, x}, 2_000
        x
      end

    # half of [1, 2, 3, 4] is 2 items, taken as one batch, then half of the rest
    assert seq == [5, 6, 7, 8, 3, 4, 2, 1]

    send(block_pid, :release)
    %{results: results, metrics: metrics} = Task.await(task, 5_000)

    assert length(results) == 10
    assert metrics.processed == %{0 => 1, 1 => 9}
    assert metrics.steals == %{0 => 0, 1 => 3}
    assert metrics.stolen == %{0 => 0, 1 => 4}
  end

  test "steal_batch: 1 takes one item at a time from the back of the victim" do
    test_pid = self()
    items = [:block, 1, 2, 3, 4, :gate, 5, 6, 7, 8]

    task =
      Task.async(fn ->
        WorkStealQueue.run(
          items,
          2,
          fn
            :block ->
              send(test_pid, {:blocked, self()})

              receive do
                :release -> :released
              end

            :gate ->
              send(test_pid, {:gated, self()})

              receive do
                :go -> :went
              end

            x ->
              send(test_pid, {:processed, x})
              x
          end,
          steal_batch: 1
        )
      end)

    assert_receive {:gated, gate_pid}, 2_000
    assert_receive {:blocked, block_pid}, 2_000
    send(gate_pid, :go)

    seq =
      for _ <- 1..8 do
        assert_receive {:processed, x}, 2_000
        x
      end

    # victim holds [1, 2, 3, 4]; single-item steals must come off the back
    assert seq == [5, 6, 7, 8, 4, 3, 2, 1]

    send(block_pid, :release)
    %{results: results, metrics: metrics} = Task.await(task, 5_000)

    assert length(results) == 10
    assert metrics.steals == %{0 => 0, 1 => 4}
    assert metrics.stolen == %{0 => 0, 1 => 4}
  end

  test "steal_batch larger than the victim queue steals it whole in one operation" do
    test_pid = self()
    items = [:block, 1, 2, 3, 4, :gate, 5, 6, 7, 8]

    task =
      Task.async(fn ->
        WorkStealQueue.run(
          items,
          2,
          fn
            :block ->
              send(test_pid, {:blocked, self()})

              receive do
                :release -> :released
              end

            :gate ->
              send(test_pid, {:gated, self()})

              receive do
                :go -> :went
              end

            x ->
              send(test_pid, {:processed, x})
              x
          end,
          steal_batch: 100
        )
      end)

    assert_receive {:gated, gate_pid}, 2_000
    assert_receive {:blocked, block_pid}, 2_000
    send(gate_pid, :go)

    seq =
      for _ <- 1..8 do
        assert_receive {:processed, x}, 2_000
        x
      end

    # only 4 items are available, so "up to 100" means all 4 in a single steal
    assert seq == [5, 6, 7, 8, 1, 2, 3, 4]

    send(block_pid, :release)
    %{results: results, metrics: metrics} = Task.await(task, 5_000)

    assert length(results) == 10
    assert metrics.steals == %{0 => 0, 1 => 1}
    assert metrics.stolen == %{0 => 0, 1 => 4}
  end

  test "duplicate items each get their own result entry" do
    items = [1, 1, 2, 2, 2, 3]
    %{results: results, metrics: metrics} = WorkStealQueue.run(items, 3, fn x -> x * 10 end)

    assert length(results) == 6
    assert Enum.sort(processed_items(results)) == Enum.sort(items)

    for %{item: item, result: result} <- results do
      assert result == item * 10
    end

    assert metrics.processed |> Map.values() |> Enum.sum() == 6
  end
end
```

Give me the complete implementation in a single file — the module(s)
alone, not the tests.
