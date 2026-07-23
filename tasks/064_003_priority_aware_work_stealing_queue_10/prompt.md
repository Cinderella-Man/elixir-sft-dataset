# Implement the missing function

Below is the complete specification of a task, followed by a working,
fully tested module that solves it — except that `sort_desc` has been
removed: every clause body is blanked to `# TODO`. Implement exactly that
function so the whole module passes the task's full test suite again.
Change nothing else — every other function, attribute, and clause must
stay exactly as shown.

## The task

# `WorkStealQueue` — Priority-Aware Work-Stealing Task Distributor

## Overview

This document specifies an Elixir module named `WorkStealQueue` that distributes **prioritized** work across N worker processes by means of a work-stealing algorithm. Within each worker, higher-priority work is to be done first. When an idle worker steals, it takes the *least urgent* work off a busy peer — leaving the busy worker to keep grinding on its most urgent items.

The deliverable is the complete implementation in a single file.

## API

One primary public function is required:

- `WorkStealQueue.run(items, worker_count, process_fn)` — `items` is a list of `{priority, payload}` tuples in which `priority` is an integer (higher = more urgent). `worker_count` is the number of workers to spawn. `process_fn` is a one-arity function applied to each **payload**. The call returns a list of `%{item: payload, priority: priority, result: term, worker_id: non_neg_integer}` maps — one per input tuple, in any order. An empty `items` list returns `[]`.

## Internal Operation

The module is expected to work as follows:

1. The input list is partitioned as evenly as possible across `worker_count` workers, **preserving input order**, so that worker `0` receives the first contiguous chunk, worker `1` the next, and so on. Each worker owns a local priority queue kept sorted such that the highest-priority item is always next.
2. All workers are spawned as `Task`s. Each worker repeatedly pops and processes its **highest-priority** local item, applying `process_fn` to the payload.
3. When a worker empties its local queue, it *steals* from the busiest worker (the one with the most items remaining). A steal takes the **lowest-priority half** of the victim's queue (the back of its sorted queue), so that the victim retains its most urgent work. If no other worker has any remaining work, the stealing worker simply exits.
4. Each worker tags every result with its own `worker_id` (`0` to `worker_count - 1`) and echoes back the item's `priority`.

## Coordination Requirements

- A shared coordination mechanism (e.g. an `Agent` or `GenServer`) must track each worker's remaining sorted queue, so that steal attempts can find the busiest worker and slice off its lowest-priority items atomically. Failed steals (victim emptied first) are to be handled gracefully, by retrying or moving on.
- `run/3` must be synchronous: it blocks until every item is processed, then returns the full result list.

## Edge Cases and Constraints

- Only OTP/stdlib may be used — no external dependencies.
- The implementation must work correctly when `worker_count` is greater than `length(items)`.
- Within a single worker, items must be processed in strictly descending priority order.
- `process_fn` may be slow or fast — faster workers should naturally pick up the low-priority slack.

## The module with `sort_desc` missing

```elixir
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

  defp sort_desc(chunk) do
    # TODO
  end

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
```

Give me only the complete implementation of `sort_desc` (including any
`@doc`/`@spec`/`@impl` lines that belong directly above it) — the
function alone, not the whole module.
