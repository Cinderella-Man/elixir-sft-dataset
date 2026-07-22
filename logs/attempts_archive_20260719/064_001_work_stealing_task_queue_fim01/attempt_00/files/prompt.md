Implement the private `try_steal/4` function.

This function is called by a worker (`process_local_queue/4`) once its own local
queue is empty. Its job is to acquire more work by stealing from a peer, or to
finish if no work remains anywhere.

`try_steal/4` receives `id` (the current worker's id), `coordinator` (the pid of
the shared `Agent` holding `%{worker_id => remaining_queue}`), `process_fn` (the
one-arity function applied to each item), and `acc` (the list of result maps this
worker has accumulated so far).

It must:

1. Find the busiest other worker to steal from by calling `find_victim(id, coordinator)`.
2. If `find_victim/2` returns `nil` — meaning no other worker has any remaining
   work — the worker is finished, so return `acc`.
3. Otherwise, given a `victim_id`, attempt to steal the back half of that victim's
   queue with `steal_half(victim_id, coordinator)`.
   - If `steal_half/2` returns `[]` — the victim emptied (or shrank below the
     steal threshold) between finding it and stealing — retry the whole steal
     attempt with a fresh scan by calling `try_steal(id, coordinator, process_fn, acc)`
     again (with the same accumulator).
   - If `steal_half/2` returns a non-empty list `stolen`, deposit those items into
     this worker's own queue in the coordinator using `Agent.update/2`. Use
     `Map.update/4` on the state keyed by `id`, defaulting to `stolen`, and when a
     queue already exists prepend the stolen items (`stolen ++ existing`) so they
     are worked through immediately. Then resume normal processing by calling
     `process_local_queue(id, coordinator, process_fn, acc)`.

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
    # TODO
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