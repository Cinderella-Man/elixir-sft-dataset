# Implement the missing function

Below is the complete specification of a task, followed by a working,
fully tested module that solves it — except that `validate_batch` has been
removed: every clause body is blanked to `# TODO`. Implement exactly that
function so the whole module passes the task's full test suite again.
Change nothing else — every other function, attribute, and clause must
stay exactly as shown.

## The task

Write me an Elixir module called `WorkStealQueue` that distributes work across N worker processes using a work-stealing algorithm and **reports instrumentation metrics** about the stealing that actually happened. On top of the results, I want to see how many steal operations each worker performed, how many items it stole, and how many it ultimately processed — plus I want to be able to tune the steal batch size.

I need one primary public function:

- `WorkStealQueue.run(items, worker_count, process_fn, opts \\ [])` — takes a list of items, a number of workers, a one-arity function, and an options keyword list. Returns a **map**:

  ```
  %{
    results: [%{item: item, result: term, worker_id: non_neg_integer}, ...],
    metrics: %{
      processed: %{worker_id => count},
      steals:    %{worker_id => count},   # number of successful steal operations
      stolen:    %{worker_id => count}    # total number of items stolen
    }
  }
  ```

  Every worker id `0..worker_count - 1` must appear as a key in each metrics sub-map (with `0` where nothing happened). The `results` list has exactly one entry per input item.

**Options:**
- `:steal_batch` — either `:half` (default: steal half of the victim's remaining queue, rounded down but always at least one item so a non-empty queue is never left un-stealable) or a positive integer `n` (steal up to `n` items per steal operation).

**How it should work internally:**

1. Partition the input list as evenly as possible across `worker_count` workers; each worker owns a local queue.
2. Spawn all workers as `Task`s. Each worker processes its local queue sequentially with `process_fn`, tagging each result with its `worker_id`.
3. When a worker empties its local queue it *steals* from the busiest worker (most items remaining), taking a contiguous batch off the *back* of the victim's queue sized according to `:steal_batch` (but never more than the victim actually holds). The stolen items keep their relative order, and the thief then processes them in that order. If no other worker has work, the stealing worker exits.
4. Each worker counts its own successful steal operations, the number of items it stole, and the number it processed; these roll up into the returned `metrics` map.

**Coordination requirements:**
- Use a shared coordination mechanism (e.g. an `Agent` or `GenServer`) tracking each worker's remaining queue so steal attempts can find the busiest worker atomically. Failed steals (victim emptied first) should be retried or skipped gracefully — a skipped/empty steal must NOT count toward the `steals` metric.
- `run/4` must be synchronous: block until every item is processed, then return the map.

**Constraints:**
- Use only OTP/stdlib — no external dependencies.
- Must work correctly when `worker_count` is greater than `length(items)`.
- `process_fn` may be slow or fast — faster workers should naturally pick up slack, which the metrics should make visible.

Give me the complete implementation in a single file.

## The module with `validate_batch` missing

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

  defp validate_batch(:half) do
    # TODO
  end

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

Give me only the complete implementation of `validate_batch` (including any
`@doc`/`@spec`/`@impl` lines that belong directly above it) — the
function alone, not the whole module.
