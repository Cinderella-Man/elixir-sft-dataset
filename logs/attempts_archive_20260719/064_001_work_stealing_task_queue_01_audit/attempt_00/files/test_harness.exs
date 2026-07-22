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

  test "a steal takes the tail of the victim's queue and leaves its front item alone" do
    test_pid = self()

    process_fn = fn item ->
      if item == 1 or item == 5 do
        send(test_pid, {:gate, item, self()})

        receive do
          :go -> :ok
        after
          5_000 -> :timeout
        end
      end

      send(test_pid, {:done, item})
      item
    end

    # Worker 0 gets [1, 2, 3, 4]; worker 1 gets [5, 6, 7, 8].
    task = Task.async(fn -> WorkStealQueue.run(Enum.to_list(1..8), 2, process_fn) end)

    # Both workers have popped their first item; worker 0's queue is frozen at
    # [2, 3, 4] while it is parked inside process_fn on item 1.
    assert_receive {:gate, 1, victim}, 1_000
    assert_receive {:gate, 5, thief}, 1_000

    # Release only the thief: it drains 6, 7, 8 and must then steal from the
    # back of the victim's [2, 3, 4] — i.e. item 4, never item 2.
    send(thief, :go)
    assert_receive {:done, 4}, 2_000

    send(victim, :go)
    results = Task.await(task, 10_000)

    worker_of = Map.new(results, fn r -> {r.item, r.worker_id} end)

    assert worker_of[4] != worker_of[1],
           "back-of-queue item 4 should have been stolen by the other worker"

    assert worker_of[2] == worker_of[1],
           "front-of-queue item 2 must stay with its owning worker"
  end

  test "four items across four workers are all in flight at once (one item each)" do
    test_pid = self()

    process_fn = fn item ->
      send(test_pid, {:started, item, self()})

      receive do
        :go -> :ok
      after
        5_000 -> :timeout
      end

      item
    end

    task = Task.async(fn -> WorkStealQueue.run([:a, :b, :c, :d], 4, process_fn) end)

    gates =
      for _ <- 1..4 do
        assert_receive {:started, item, pid}, 2_000
        {item, pid}
      end

    # All four items are parked simultaneously, which is only possible if each
    # worker started with exactly one item.
    assert Enum.sort(Enum.map(gates, fn {item, _pid} -> item end)) == [:a, :b, :c, :d]
    assert length(Enum.uniq(Enum.map(gates, fn {_item, pid} -> pid end))) == 4

    Enum.each(gates, fn {_item, pid} -> send(pid, :go) end)

    results = Task.await(task, 10_000)
    assert length(results) == 4
    assert length(Enum.uniq(Enum.map(results, & &1.worker_id))) == 4
  end

  test "a worker does not begin its next item before the current one returns" do
    test_pid = self()

    process_fn = fn item ->
      send(test_pid, {:started, item, self()})

      receive do
        :go -> :ok
      after
        5_000 -> :timeout
      end

      item
    end

    task = Task.async(fn -> WorkStealQueue.run([1, 2], 1, process_fn) end)

    assert_receive {:started, 1, worker}, 2_000
    refute_receive {:started, 2, _}, 200

    send(worker, :go)
    assert_receive {:started, 2, ^worker}, 2_000
    send(worker, :go)

    results = Task.await(task, 10_000)
    assert Enum.sort(Enum.map(results, & &1.item)) == [1, 2]
  end

  test "run/3 stays blocked while one item is still inside process_fn" do
    test_pid = self()

    process_fn = fn item ->
      if item == :gated do
        send(test_pid, {:gate, self()})

        receive do
          :go -> :ok
        after
          5_000 -> :timeout
        end
      end

      item
    end

    spawn_link(fn ->
      send(test_pid, {:returned, WorkStealQueue.run([:gated, :b, :c], 3, process_fn)})
    end)

    assert_receive {:gate, worker}, 2_000
    refute_receive {:returned, _}, 300

    send(worker, :go)
    assert_receive {:returned, results}, 5_000
    assert Enum.sort(Enum.map(results, & &1.item)) == [:b, :c, :gated]
  end

  test "repeated equal items each produce their own result entry" do
    results = WorkStealQueue.run([:dup, :dup, :dup, :dup, :dup], 2, fn x -> {x, :ok} end)

    assert length(results) == 5

    for %{item: item, result: result, worker_id: wid} <- results do
      assert item == :dup
      assert result == {:dup, :ok}
      assert wid >= 0 and wid < 2
    end
  end
end
