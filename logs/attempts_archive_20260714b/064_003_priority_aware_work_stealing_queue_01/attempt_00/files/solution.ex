defmodule WorkStealQueue do
  @moduledoc """
  Priority-aware work-stealing task queue.

  Items are `{priority, payload}` tuples (higher priority = more urgent). Each
  worker owns a local queue kept sorted in descending priority order and always
  processes its most urgent item next. When a worker empties its queue it steals
  the **lowest-priority half** of the busiest peer's queue — so a busy worker
  keeps its most urgent work and only sheds its least urgent items.

  Coordination goes through an `Agent` holding `%{worker_id => sorted_queue}`,
  giving each steal attempt an atomic snapshot of all queues.

  ## Example

      WorkStealQueue.run([{5, :urgent}, {1, :later}], 2, fn p -> {:ran, p} end)
      # => [%{item: :urgent, priority: 5, result: {:ran, :urgent}, worker_id: 0}, ...]
  """

  @type item :: {integer(), any()}

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  @doc """
  Process every `{priority, payload}` in `items` across `worker_count` workers,
  highest priority first, stealing low-priority work when idle. Returns one
  result map per item (any order). Blocks until everything is processed.
  """
  @spec run([item()], pos_integer(), (any() -> any())) :: [
          %{item: any(), priority: integer(), result: any(), worker_id: non_neg_integer()}
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
      {:ok, {priority, payload}} ->
        result = process_fn.(payload)
        entry = %{item: payload, priority: priority, result: result, worker_id: id}
        process_local_queue(id, coordinator, process_fn, [entry | acc])

      :empty ->
        try_steal(id, coordinator, process_fn, acc)
    end
  end

  defp try_steal(id, coordinator, process_fn, acc) do
    case find_victim(id, coordinator) do
      nil ->
        acc

      victim_id ->
        case steal_low_half(victim_id, coordinator) do
          [] ->
            try_steal(id, coordinator, process_fn, acc)

          stolen ->
            # `stolen` is a sorted-descending suffix; merge into our (empty or
            # residual) queue keeping descending order.
            Agent.update(coordinator, fn state ->
              Map.update(state, id, stolen, fn existing -> merge_desc(existing, stolen) end)
            end)

            process_local_queue(id, coordinator, process_fn, acc)
        end
    end
  end

  # ---------------------------------------------------------------------------
  # Coordinator operations
  # ---------------------------------------------------------------------------

  @spec pop_item(non_neg_integer(), pid()) :: {:ok, item()} | :empty
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

  # Take the lowest-priority half (the back of the descending-sorted queue).
  @spec steal_low_half(non_neg_integer(), pid()) :: [item()]
  defp steal_low_half(victim_id, coordinator) do
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
  # Sorted-queue helpers
  # ---------------------------------------------------------------------------

  defp sort_desc(chunk), do: Enum.sort_by(chunk, fn {priority, _payload} -> priority end, :desc)

  # Merge two descending-sorted lists into one descending-sorted list.
  defp merge_desc(a, []), do: a
  defp merge_desc([], b), do: b

  defp merge_desc([{pa, _} = ha | ta] = left, [{pb, _} = hb | tb] = right) do
    if pa >= pb do
      [ha | merge_desc(ta, right)]
    else
      [hb | merge_desc(left, tb)]
    end
  end

  # ---------------------------------------------------------------------------
  # Partitioning
  # ---------------------------------------------------------------------------

  @spec partition([item()], pos_integer()) :: [[item()]]
  defp partition(items, n) do
    total = length(items)
    base_size = div(total, n)
    extras = rem(total, n)

    {chunks, _remaining} =
      Enum.reduce(0..(n - 1), {[], items}, fn i, {acc, rest} ->
        chunk_size = if i < extras, do: base_size + 1, else: base_size
        {chunk, tail} = Enum.split(rest, chunk_size)
        {[sort_desc(chunk) | acc], tail}
      end)

    Enum.reverse(chunks)
  end
end