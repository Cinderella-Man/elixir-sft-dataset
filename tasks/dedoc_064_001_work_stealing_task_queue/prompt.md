# Document this module

Below is a complete, working, tested Elixir module. Its behavior is correct
and must not change — but every piece of documentation has been stripped.

Add the missing documentation and typespecs:

- a `@moduledoc` that explains what the module does and how it is used,
- a `@doc` for every public function,
- a `@spec` for every public function (add `@type`s where they make the
  specs clearer).

Do not change any behavior: every function clause, guard, and expression
must keep working exactly as it does now. Do not rename anything, do not
"improve" the code, and do not add or remove functions. Give me the
complete documented module in a single file.

## The module

```elixir
defmodule WorkStealQueue do
  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

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

  # Atomically remove the back half of the victim's queue and return it.
  # Stealing from the *back* is safe: the victim consumes from the *front*, so
  # the items we take are the furthest from being processed imminently.
  # Returns `[]` if the victim's queue is now too small to bother stealing from.
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
