# Write the missing @spec

Below is a complete, working module — except that the `@spec` for
`find_victim/2` has been removed; its place is marked `# TODO: @spec`.
Write exactly that typespec: one `@spec` attribute for `find_victim/2`,
consistent with the function's arguments, guards, and every return shape
the implementation can produce. Change nothing else.

## The module with the `@spec` for `find_victim/2` missing

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

  # TODO: @spec
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

Give me only the `@spec` attribute — the attribute alone (however many
lines it spans), not the whole module.
