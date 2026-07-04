# Fill in the middle: implement the blanked test

Below is a module and its ExUnit test harness with the body of ONE `test` removed
(marked `# TODO`). The test's name states what it must verify. Implement just that one
test so the harness passes for a correct implementation of the module.

## Module under test

```elixir
defmodule WorkStealQueue do
  @moduledoc """
  Instrumented work-stealing task queue.

  Distributes work across N worker `Task`s using a work-stealing algorithm and
  returns, alongside the results, a `metrics` map describing how much stealing
  actually occurred: successful steal operations per worker, items stolen per
  worker, and items processed per worker.

  The steal batch size is tunable via `:steal_batch` — `:half` (default) or a
  positive integer. Coordination goes through an `Agent` holding
  `%{worker_id => remaining_queue}`.

  ## Example

      WorkStealQueue.run(Enum.to_list(1..10), 3, &(&1 * 2), steal_batch: 2)
      # => %{results: [...], metrics: %{processed: %{...}, steals: %{...}, stolen: %{...}}}
  """

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  @doc """
  Process every item across `worker_count` workers and return a map with the
  `results` list and a `metrics` map. Blocks until all items are processed.

  Options:
    * `:steal_batch` — `:half` (default) or a positive integer.
  """
  @spec run(list(), pos_integer(), (any() -> any()), keyword()) :: %{
          results: [%{item: any(), result: any(), worker_id: non_neg_integer()}],
          metrics: %{
            processed: %{non_neg_integer() => non_neg_integer()},
            steals: %{non_neg_integer() => non_neg_integer()},
            stolen: %{non_neg_integer() => non_neg_integer()}
          }
        }
  def run(items, worker_count, process_fn, opts \\ [])
      when is_list(items) and is_integer(worker_count) and worker_count > 0 and
             is_function(process_fn, 1) and is_list(opts) do
    batch = validate_batch(Keyword.get(opts, :steal_batch, :half))
    partitions = partition(items, worker_count)

    {:ok, coordinator} =
      Agent.start_link(fn ->
        partitions
        |> Enum.with_index()
        |> Map.new(fn {queue, id} -> {id, queue} end)
      end)

    worker_returns =
      0..(worker_count - 1)
      |> Enum.map(fn id ->
        Task.async(fn -> run_worker(id, coordinator, process_fn, batch) end)
      end)
      |> Task.await_many(:infinity)

    Agent.stop(coordinator)

    %{
      results: Enum.flat_map(worker_returns, & &1.results),
      metrics: build_metrics(worker_returns, worker_count)
    }
  end

  defp validate_batch(:half), do: :half
  defp validate_batch(n) when is_integer(n) and n > 0, do: n

  # ---------------------------------------------------------------------------
  # Worker logic
  # ---------------------------------------------------------------------------

  defp run_worker(id, coordinator, process_fn, batch) do
    loop(id, coordinator, process_fn, batch, %{
      worker_id: id,
      results: [],
      steals: 0,
      stolen: 0
    })
  end

  defp loop(id, coordinator, process_fn, batch, acc) do
    case pop_item(id, coordinator) do
      {:ok, item} ->
        entry = %{item: item, result: process_fn.(item), worker_id: id}
        loop(id, coordinator, process_fn, batch, %{acc | results: [entry | acc.results]})

      :empty ->
        steal_phase(id, coordinator, process_fn, batch, acc)
    end
  end

  defp steal_phase(id, coordinator, process_fn, batch, acc) do
    case find_victim(id, coordinator) do
      nil ->
        acc

      victim_id ->
        case steal(victim_id, coordinator, batch) do
          [] ->
            # Victim emptied before we could take anything; a skipped steal must
            # not count toward the metric. Re-scan.
            steal_phase(id, coordinator, process_fn, batch, acc)

          stolen ->
            Agent.update(coordinator, fn state ->
              Map.update(state, id, stolen, fn existing -> stolen ++ existing end)
            end)

            acc = %{acc | steals: acc.steals + 1, stolen: acc.stolen + length(stolen)}
            loop(id, coordinator, process_fn, batch, acc)
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

  # Take up to `batch` items from the back of the victim's queue.
  @spec steal(non_neg_integer(), pid(), :half | pos_integer()) :: list()
  defp steal(victim_id, coordinator, batch) do
    Agent.get_and_update(coordinator, fn state ->
      queue = Map.fetch!(state, victim_id)
      len = length(queue)

      if len == 0 do
        {[], state}
      else
        steal_count = min(batch_size(batch, len), len)
        keep_count = len - steal_count
        {keep, stolen} = Enum.split(queue, keep_count)
        {stolen, Map.put(state, victim_id, keep)}
      end
    end)
  end

  defp batch_size(:half, len), do: max(div(len, 2), 1)
  defp batch_size(n, _len) when is_integer(n) and n > 0, do: n

  # ---------------------------------------------------------------------------
  # Metrics aggregation
  # ---------------------------------------------------------------------------

  defp build_metrics(worker_returns, worker_count) do
    zero = for i <- 0..(worker_count - 1), into: %{}, do: {i, 0}

    Enum.reduce(
      worker_returns,
      %{processed: zero, steals: zero, stolen: zero},
      fn r, metrics ->
        %{
          processed: Map.put(metrics.processed, r.worker_id, length(r.results)),
          steals: Map.put(metrics.steals, r.worker_id, r.steals),
          stolen: Map.put(metrics.stolen, r.worker_id, r.stolen)
        }
      end
    )
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
    # TODO
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
```
