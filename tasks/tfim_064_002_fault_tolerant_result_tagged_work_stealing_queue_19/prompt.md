# Fill in the middle: implement the blanked test

Below is a module and its ExUnit test harness with the body of ONE `test` removed
(marked `# TODO`). The test's name states what it must verify. Implement just that one
test so the harness passes for a correct implementation of the module.

## Module under test

```elixir
defmodule WorkStealQueue do
  @moduledoc """
  Fault-tolerant, result-tagged work-stealing task queue.

  Distributes work across N worker `Task`s using a work-stealing algorithm.
  Each worker owns a local queue; when it empties it steals the back-half of
  the busiest peer's queue. Coordination goes through an `Agent` whose state is
  a plain map `%{worker_id => [remaining_items]}`, giving each steal attempt an
  atomic snapshot of all queues.

  Unlike a plain work-stealing queue, every `process_fn` invocation is wrapped
  so that raises, throws, and exits are *captured* and turned into a tagged
  `{:error, %{kind: ..., reason: ...}}` result. A misbehaving item can never
  kill its worker or lose sibling items.

  ## Example

      WorkStealQueue.run([1, 2, 3], 2, fn
        2 -> raise "boom"
        n -> n * 10
      end)
      # => [%{item: 1, result: {:ok, 10}, worker_id: 0},
      #     %{item: 2, result: {:error, %{kind: :error, reason: "boom"}}, worker_id: 0},
      #     %{item: 3, result: {:ok, 30}, worker_id: 1}]   (order varies)
  """

  @type tagged_result :: {:ok, any()} | {:error, %{kind: :error | :throw | :exit, reason: any()}}

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  @doc """
  Process every item by applying `process_fn` across `worker_count` parallel,
  fault-tolerant workers. Returns one result map per item (any order). Blocks
  until all items have been processed.
  """
  @spec run(list(), pos_integer(), (any() -> any())) :: [
          %{item: any(), result: tagged_result(), worker_id: non_neg_integer()}
        ]
  def run(items, worker_count, process_fn)
      when is_list(items) and is_integer(worker_count) and worker_count > 0 and
             is_function(process_fn, 1) do
    partitions = partition(items, worker_count)

    {:ok, coordinator} =
      Agent.start_link(fn ->
        partitions
        |> Enum.with_index()
        |> Map.new(fn {queue, id} -> {id, queue} end)
      end)

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

  defp run_worker(id, coordinator, process_fn) do
    process_local_queue(id, coordinator, process_fn, [])
  end

  defp process_local_queue(id, coordinator, process_fn, acc) do
    case pop_item(id, coordinator) do
      {:ok, item} ->
        result = safe_apply(process_fn, item)
        entry = %{item: item, result: result, worker_id: id}
        process_local_queue(id, coordinator, process_fn, [entry | acc])

      :empty ->
        try_steal(id, coordinator, process_fn, acc)
    end
  end

  # Wrap a single item's processing so raise/throw/exit become tagged results.
  @spec safe_apply((any() -> any()), any()) :: tagged_result()
  defp safe_apply(process_fn, item) do
    try do
      {:ok, process_fn.(item)}
    rescue
      e -> {:error, %{kind: :error, reason: Exception.message(e)}}
    catch
      :throw, value -> {:error, %{kind: :throw, reason: value}}
      :exit, reason -> {:error, %{kind: :exit, reason: reason}}
    end
  end

  defp try_steal(id, coordinator, process_fn, acc) do
    case find_victim(id, coordinator) do
      nil ->
        acc

      victim_id ->
        case steal_half(victim_id, coordinator) do
          [] ->
            try_steal(id, coordinator, process_fn, acc)

          stolen ->
            Agent.update(coordinator, fn state ->
              Map.update(state, id, stolen, fn existing -> stolen ++ existing end)
            end)

            process_local_queue(id, coordinator, process_fn, acc)
        end
    end
  end

  # ---------------------------------------------------------------------------
  # Coordinator operations
  # ---------------------------------------------------------------------------

  @spec pop_item(non_neg_integer(), pid()) :: {:ok, any()} | :empty
  defp pop_item(id, coordinator) do
    Agent.get_and_update(coordinator, fn state ->
      case Map.fetch!(state, id) do
        [] -> {:empty, state}
        [head | tail] -> {{:ok, head}, Map.put(state, id, tail)}
      end
    end)
  end

  @spec find_victim(non_neg_integer(), pid()) :: non_neg_integer() | nil
  defp find_victim(thief_id, coordinator) do
    Agent.get(coordinator, fn state ->
      state
      |> Enum.reject(fn {id, queue} -> id == thief_id or queue == [] end)
      |> case do
        [] ->
          nil

        candidates ->
          {victim_id, _queue} = Enum.max_by(candidates, fn {_id, q} -> length(q) end)
          victim_id
      end
    end)
  end

  @spec steal_half(non_neg_integer(), pid()) :: list()
  defp steal_half(victim_id, coordinator) do
    Agent.get_and_update(coordinator, fn state ->
      queue = Map.fetch!(state, victim_id)
      len = length(queue)

      if len < 2 do
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

  @spec partition(list(), pos_integer()) :: [list()]
  defp partition(items, n) do
    total = length(items)
    base_size = div(total, n)
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
    # TODO
  end
end
```
