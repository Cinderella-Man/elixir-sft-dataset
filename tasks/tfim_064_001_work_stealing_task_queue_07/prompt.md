# Fill in the middle: implement the blanked test

Below is a module and its ExUnit test harness with the body of ONE `test` removed
(marked `# TODO`). The test's name states what it must verify. Implement just that one
test so the harness passes for a correct implementation of the module.

## Module under test

```elixir
defmodule WorkStealQueue do
  @moduledoc """
  Distributes work across N worker processes using a work-stealing algorithm.

  Each worker owns a local queue. When a worker exhausts its queue it inspects
  the shared coordinator to find the busiest peer and steals the back-half of
  that peer's remaining work.  The coordinator is an `Agent` whose state is a
  plain map `%{worker_id => [remaining_items]}`, giving each steal attempt an
  atomic snapshot of all queues.

  ## Example

      results =
        WorkStealQueue.run(1..20 |> Enum.to_list(), 4, fn n ->
          Process.sleep(:rand.uniform(50))
          n * n
        end)

      # => [%{item: 3, result: 9, worker_id: 2}, ...]  (order varies)
  """

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  @doc """
  Process every item in `items` by applying `process_fn` across `worker_count`
  parallel workers, then return a list of result maps (one per item, any order).

  Each map has the shape:
      %{item: original_item, result: process_fn_return_value, worker_id: 0..worker_count-1}

  `run/3` blocks until every item has been processed.
  """
  @spec run(list(), pos_integer(), (any() -> any())) :: [
          %{item: any(), result: any(), worker_id: non_neg_integer()}
        ]
  def run(items, worker_count, process_fn)
      when is_list(items) and is_integer(worker_count) and worker_count > 0 and
             is_function(process_fn, 1) do
    # Divide the input list into `worker_count` chunks as evenly as possible.
    partitions = partition(items, worker_count)

    # The coordinator Agent holds a map of %{id => remaining_queue}.
    # All queue mutations (pop, steal) go through this Agent so they are
    # serialised and workers see a consistent picture of who has work left.
    {:ok, coordinator} =
      Agent.start_link(fn ->
        partitions
        |> Enum.with_index()
        |> Map.new(fn {queue, id} -> {id, queue} end)
      end)

    # Spawn one Task per worker and await all of them.
    results =
      0..(worker_count - 1)
      |> Enum.map(fn id ->
        Task.async(fn -> run_worker(id, coordinator, process_fn) end)
      end)
      |> Task.await_many(:infinity)
      |> List.flatten()

    Agent.stop(coordinator)
    results
  end

  # ---------------------------------------------------------------------------
  # Worker logic
  # ---------------------------------------------------------------------------

  # Entry-point for each worker Task.  Results accumulate tail-recursively.
  defp run_worker(id, coordinator, process_fn) do
    process_local_queue(id, coordinator, process_fn, _acc = [])
  end

  # Process items from this worker's own queue until it is empty, then try to
  # steal.  Using an accumulator keeps the recursion stack-friendly.
  defp process_local_queue(id, coordinator, process_fn, acc) do
    case pop_item(id, coordinator) do
      {:ok, item} ->
        result = process_fn.(item)
        entry = %{item: item, result: result, worker_id: id}
        process_local_queue(id, coordinator, process_fn, [entry | acc])

      :empty ->
        try_steal(id, coordinator, process_fn, acc)
    end
  end

  # When the local queue is empty, look for the busiest other worker and steal
  # half its remaining items.  If no work exists anywhere, we are done.
  defp try_steal(id, coordinator, process_fn, acc) do
    case find_victim(id, coordinator) do
      nil ->
        # No other worker has any remaining work — we are finished.
        acc

      victim_id ->
        case steal_half(victim_id, coordinator) do
          [] ->
            # The victim emptied its queue between the time we identified it
            # and the time we tried to steal.  Try again with a fresh scan.
            try_steal(id, coordinator, process_fn, acc)

          stolen ->
            # Deposit the stolen items into our own queue and resume normal
            # processing.  Prepend so we work through them immediately.
            Agent.update(coordinator, fn state ->
              Map.update(state, id, stolen, fn existing -> stolen ++ existing end)
            end)

            process_local_queue(id, coordinator, process_fn, acc)
        end
    end
  end

  # ---------------------------------------------------------------------------
  # Coordinator operations (all go through the Agent)
  # ---------------------------------------------------------------------------

  # Atomically pop the head item from worker `id`'s queue.
  @spec pop_item(non_neg_integer(), pid()) :: {:ok, any()} | :empty
  defp pop_item(id, coordinator) do
    Agent.get_and_update(coordinator, fn state ->
      case Map.fetch!(state, id) do
        [] ->
          {:empty, state}

        [head | tail] ->
          {{:ok, head}, Map.put(state, id, tail)}
      end
    end)
  end

  # Return the id of the worker (other than `thief_id`) with the longest queue,
  # or `nil` if every other worker's queue is empty.
  @spec find_victim(non_neg_integer(), pid()) :: non_neg_integer() | nil
  defp find_victim(thief_id, coordinator) do
    Agent.get(coordinator, fn state ->
      state
      # A queue needs at least TWO items to be worth targeting — steal_half
      # refuses single-item queues, so selecting one would spin through a
      # fruitless find/steal loop (hot-looping on the Agent) for as long as
      # the victim stays busy inside process_fn.
      |> Enum.reject(fn {id, queue} ->
        id == thief_id or match?([], queue) or match?([_], queue)
      end)
      |> case do
        [] ->
          nil

        candidates ->
          {victim_id, _queue} = Enum.max_by(candidates, fn {_id, q} -> length(q) end)
          victim_id
      end
    end)
  end

  # Atomically remove the back half of the victim's queue and return it.
  # Stealing from the *back* is safe: the victim consumes from the *front*, so
  # the items we take are the furthest from being processed imminently.
  # Returns `[]` if the victim's queue is now too small to bother stealing from.
  @spec steal_half(non_neg_integer(), pid()) :: list()
  defp steal_half(victim_id, coordinator) do
    Agent.get_and_update(coordinator, fn state ->
      queue = Map.fetch!(state, victim_id)
      len = length(queue)

      if len < 2 do
        # Not worth stealing a single item that the victim is about to take.
        {[], state}
      else
        steal_count = div(len, 2)
        keep_count = len - steal_count
        {keep, stolen} = Enum.split(queue, keep_count)
        {stolen, Map.put(state, victim_id, keep)}
      end
    end)
  end

  # ---------------------------------------------------------------------------
  # Partitioning
  # ---------------------------------------------------------------------------

  # Divide `items` into `n` chunks as evenly as possible.
  # The first `rem(length, n)` chunks get one extra item.
  # Always returns exactly `n` lists (some may be `[]` when n > length(items)).
  @spec partition(list(), pos_integer()) :: [list()]
  defp partition(items, n) do
    total = length(items)
    base_size = div(total, n)
    # How many workers get one extra item
    extras = rem(total, n)

    {chunks, _remaining} =
      Enum.reduce(0..(n - 1), {[], items}, fn i, {acc, rest} ->
        chunk_size = if i < extras, do: base_size + 1, else: base_size
        {chunk, tail} = Enum.split(rest, chunk_size)
        {[chunk | acc], tail}
      end)

    Enum.reverse(chunks)
  end
end
```

## Test harness — implement the `# TODO` test

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
    # TODO
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

  test "run/3 refuses a worker_count that is not a positive integer" do
    for bad <- [0, -3, 1.5, :two] do
      assert_raise FunctionClauseError, fn ->
        WorkStealQueue.run([1, 2, 3], bad, fn x -> x end)
      end
    end
  end

  test "an idle worker steals from the BACK of a busy peer's queue" do
    test_pid = self()

    # Six items across two workers partition [1, 2, 3] / [4, 5, 6]. Worker 0
    # parks inside process_fn on item 1 (queue left: [2, 3]); worker 1 races
    # through its own queue and MUST steal — and the steal takes the BACK
    # half, so item 3 lands on worker 1 while item 2 stays with worker 0
    # (a single-item queue is never a victim).
    blocker = fn
      1 ->
        send(test_pid, {:blocked, self()})

        receive do
          :go -> :one
        end

      n ->
        n
    end

    task = Task.async(fn -> WorkStealQueue.run([1, 2, 3, 4, 5, 6], 2, blocker) end)

    assert_receive {:blocked, worker_zero}, 1_000
    # Give worker 1 time to drain its own queue and perform the steal.
    Process.sleep(150)
    send(worker_zero, :go)

    results = Task.await(task, 5_000)
    by_item = Map.new(results, fn %{item: item, worker_id: id} -> {item, id} end)

    assert by_item[1] == 0
    assert by_item[2] == 0
    assert by_item[3] == 1
    assert by_item[4] == 1
    assert by_item[5] == 1
    assert by_item[6] == 1
  end
end
```
