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

  test "an idle worker steals from the peer holding the most remaining items" do
    parent = self()

    items = [
      {4, 4},
      {3, 3},
      {2, 2},
      {1, 1},
      {8, 8},
      {7, 7},
      {6, 6},
      {5, 5},
      {12, 12},
      {11, 11},
      {10, 10},
      {9, 9}
    ]

    gate = fn payload ->
      send(parent, {:started, payload, self()})

      receive do
        :go -> payload
      after
        5000 -> payload
      end
    end

    task = Task.async(fn -> WorkStealQueue.run(items, 3, gate) end)

    # Chunks are [4,3,2,1] / [8,7,6,5] / [12,11,10,9]; every worker pops its head.
    assert_receive {:started, 4, w0}, 2000
    assert_receive {:started, 8, w1}, 2000
    assert_receive {:started, 12, w2}, 2000

    # Let worker 1 advance one item so it holds fewer items than worker 2.
    send(w1, :go)
    assert_receive {:started, 7, ^w1}, 2000

    # Drain worker 0's whole chunk; it then empties and must steal.
    send(w0, :go)
    assert_receive {:started, 3, ^w0}, 2000
    send(w0, :go)
    assert_receive {:started, 2, ^w0}, 2000
    send(w0, :go)
    assert_receive {:started, 1, ^w0}, 2000
    send(w0, :go)

    # Worker 2 still holds [11,10,9] (3 items), worker 1 holds [6,5] (2 items).
    # The busiest peer is worker 2, so its least urgent item (9) must move.
    assert_receive {:started, 9, ^w0}, 2000
    send(w0, :go)
    send(w2, :go)

    for _ <- 1..4 do
      assert_receive {:started, _payload, pid}, 5000
      send(pid, :go)
    end

    assert length(Task.await(task, 5000)) == 12
  end

  test "a steal moves exactly the back half of the victim's remaining queue" do
    parent = self()

    items = [
      {10, 10},
      {9, 9},
      {8, 8},
      {7, 7},
      {6, 6},
      {5, 5},
      {4, 4},
      {3, 3},
      {2, 2},
      {1, 1}
    ]

    gate = fn payload ->
      send(parent, {:started, payload, self()})

      receive do
        :go -> payload
      after
        5000 -> payload
      end
    end

    task = Task.async(fn -> WorkStealQueue.run(items, 2, gate) end)

    assert_receive {:started, 10, w0}, 2000
    assert_receive {:started, 5, w1}, 2000

    # Drain worker 1's chunk [5,4,3,2,1] so it goes idle while worker 0 is
    # still blocked on 10 and holds exactly [9,8,7,6].
    send(w1, :go)
    assert_receive {:started, 4, ^w1}, 2000
    send(w1, :go)
    assert_receive {:started, 3, ^w1}, 2000
    send(w1, :go)
    assert_receive {:started, 2, ^w1}, 2000
    send(w1, :go)
    assert_receive {:started, 1, ^w1}, 2000
    send(w1, :go)

    # Half of 4 remaining is 2: the thief must get [7, 6] and start on 7.
    assert_receive {:started, 7, ^w1}, 2000
    send(w1, :go)
    assert_receive {:started, 6, ^w1}, 2000
    send(w1, :go)
    send(w0, :go)

    for _ <- 1..2 do
      assert_receive {:started, _payload, pid}, 5000
      send(pid, :go)
    end

    results = Task.await(task, 5000)
    assert length(results) == 10

    worker_by_priority = Map.new(results, fn r -> {r.priority, r.worker_id} end)
    assert worker_by_priority[7] == worker_by_priority[5]
    assert worker_by_priority[6] == worker_by_priority[5]
  end

  test "each worker starts on the head of its own even contiguous chunk" do
    parent = self()
    items = for p <- 1..6, do: {p, p}

    gate = fn payload ->
      send(parent, {:started, payload, self()})

      receive do
        :go -> payload
      after
        5000 -> payload
      end
    end

    task = Task.async(fn -> WorkStealQueue.run(items, 3, gate) end)

    # No worker can empty (and therefore steal) before every worker has popped
    # its own head, so the first payload per worker pins the partition.
    seen =
      for _ <- 1..6 do
        assert_receive {:started, payload, pid}, 5000
        send(pid, :go)
        {pid, payload}
      end

    results = Task.await(task, 5000)
    assert length(results) == 6

    firsts =
      seen
      |> Enum.reduce(%{}, fn {pid, payload}, acc -> Map.put_new(acc, pid, payload) end)
      |> Map.values()
      |> Enum.sort()

    # 6 items / 3 workers => chunks [1,2] [3,4] [5,6]; heads are 2, 4 and 6.
    assert firsts == [2, 4, 6]
  end

  test "identical priority/payload tuples each produce their own result map" do
    items = [{1, :a}, {1, :a}, {2, :b}, {2, :b}, {2, :b}]
    results = WorkStealQueue.run(items, 3, fn payload -> {:ok, payload} end)

    assert length(results) == 5
    assert Enum.sort(payloads(results)) == [:a, :a, :b, :b, :b]
    assert Enum.all?(results, fn r -> r.result == {:ok, r.item} end)
    assert Enum.all?(results, fn r -> r.priority == if(r.item == :a, do: 1, else: 2) end)
  end

  test "every process_fn call has completed by the time run/3 returns" do
    {:ok, counter} = Agent.start_link(fn -> 0 end)
    items = for p <- 1..25, do: {p, p}

    results =
      WorkStealQueue.run(items, 4, fn payload ->
        Agent.update(counter, fn n -> n + 1 end)
        payload
      end)

    observed = Agent.get(counter, & &1)
    Agent.stop(counter)

    assert observed == 25
    assert length(results) == 25
  end
end
