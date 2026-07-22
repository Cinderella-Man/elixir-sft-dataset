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

  # -------------------------------------------------------
  # Victim selection: the busiest peer is the steal target
  # -------------------------------------------------------

  test "an idle worker steals from the peer holding the most remaining items" do
    # Worker 0 is the deep queue (7 items left), worker 1 the shallow one
    # (4 items left), worker 2 the thief. Only the deep worker may be robbed.
    probe = run_steal_probe([:deep, :shallow, :thief])

    assert probe.stolen, "expected the idle worker to steal before the deadline"
    assert length(probe.results) == 24

    first_stolen = Enum.find(probe.order, &stealable?/1)
    assert match?({:deep, _}, first_stolen)

    by_payload = Map.new(probe.results, fn r -> {r.item, r} end)
    assert by_payload[first_stolen].worker_id == 2

    # The victim keeps grinding on its own most urgent item.
    assert by_payload[{:deep, 30}].worker_id == 0
  end

  test "victim choice follows queue length rather than worker id" do
    # Same scenario with the roles rotated: worker 0 is now the shallow peer and
    # worker 2 the deep one, so the busiest victim is no longer the lowest id.
    probe = run_steal_probe([:shallow, :thief, :deep])

    assert probe.stolen, "expected the idle worker to steal before the deadline"
    assert length(probe.results) == 24

    first_stolen = Enum.find(probe.order, &stealable?/1)
    assert match?({:deep, _}, first_stolen)

    by_payload = Map.new(probe.results, fn r -> {r.item, r} end)
    assert by_payload[first_stolen].worker_id == 1
    assert by_payload[{:deep, 30}].worker_id == 2
  end

  # -------------------------------------------------------
  # Steal-probe scaffolding
  # -------------------------------------------------------

  # Three chunks of 8 items each, so a 24-item input across 3 workers hands one
  # whole chunk to each worker in input order. The :deep worker parks inside
  # process_fn while holding its most urgent item, leaving 7 queued; the
  # :shallow worker parks after burning three fast items, leaving 4 queued; the
  # :thief worker finishes its own chunk only once both peers are parked, so the
  # steal that follows has exactly one busiest victim.
  defp chunk(:deep) do
    [{90, :gate_deep}] ++ Enum.map([30, 29, 28, 27, 26, 25, 24], fn p -> {p, {:deep, p}} end)
  end

  defp chunk(:shallow) do
    Enum.map([60, 59, 58], fn p -> {p, {:fast, p}} end) ++
      [{57, :gate_shallow}] ++
      Enum.map([20, 19, 18, 17], fn p -> {p, {:shallow, p}} end)
  end

  defp chunk(:thief) do
    Enum.map([50, 49, 48, 47, 46, 45, 44], fn p -> {p, {:own, p}} end) ++ [{43, :gate_thief}]
  end

  # Payloads that can only be touched by a thief while both peers are parked.
  defp stealable?({:deep, _}), do: true
  defp stealable?({:shallow, _}), do: true
  defp stealable?(_), do: false

  defp run_steal_probe(slots) do
    items = Enum.flat_map(slots, &chunk/1)
    {:ok, log} = Agent.start_link(fn -> [] end)
    {:ok, gate} = Agent.start_link(fn -> MapSet.new() end)

    process_fn = fn payload ->
      Agent.update(log, fn acc -> [payload | acc] end)
      hold(gate, payload)
      payload
    end

    task = Task.async(fn -> WorkStealQueue.run(items, 3, process_fn) end)

    stolen = poll_until(4_000, fn -> Enum.any?(Agent.get(log, & &1), &stealable?/1) end)

    set_flag(gate, :release)
    results = Task.await(task, 20_000)
    order = log |> Agent.get(& &1) |> Enum.reverse()
    Agent.stop(log)
    Agent.stop(gate)

    %{stolen: stolen, order: order, results: results}
  end

  defp hold(gate, :gate_deep) do
    set_flag(gate, :deep_parked)
    poll_until(4_000, fn -> flag?(gate, :release) end)
  end

  defp hold(gate, :gate_shallow) do
    set_flag(gate, :shallow_parked)
    poll_until(4_000, fn -> flag?(gate, :release) end)
  end

  defp hold(gate, :gate_thief) do
    poll_until(4_000, fn -> flag?(gate, :deep_parked) and flag?(gate, :shallow_parked) end)
  end

  defp hold(_gate, _payload), do: :ok

  defp set_flag(gate, flag), do: Agent.update(gate, fn flags -> MapSet.put(flags, flag) end)

  defp flag?(gate, flag), do: Agent.get(gate, fn flags -> MapSet.member?(flags, flag) end)

  # Polls until the condition holds or the budget runs out; true when observed.
  defp poll_until(budget_ms, check) do
    cond do
      check.() ->
        true

      budget_ms <= 0 ->
        false

      true ->
        Process.sleep(5)
        poll_until(budget_ms - 5, check)
    end
  end
end
