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
- `:steal_batch` — either `:half` (default: steal half of the victim's remaining queue) or a positive integer `n` (steal up to `n` items per steal operation).

**How it should work internally:**

1. Partition the input list as evenly as possible across `worker_count` workers; each worker owns a local queue.
2. Spawn all workers as `Task`s. Each worker processes its local queue sequentially with `process_fn`, tagging each result with its `worker_id`.
3. When a worker empties its local queue it *steals* from the busiest worker (most items remaining), taking items from the back of the victim's queue according to `:steal_batch`. If no other worker has work, the stealing worker exits.
4. Each worker counts its own successful steal operations, the number of items it stole, and the number it processed; these roll up into the returned `metrics` map.

**Coordination requirements:**
- Use a shared coordination mechanism (e.g. an `Agent` or `GenServer`) tracking each worker's remaining queue so steal attempts can find the busiest worker atomically. Failed steals (victim emptied first) should be retried or skipped gracefully — a skipped/empty steal must NOT count toward the `steals` metric.
- `run/4` must be synchronous: block until every item is processed, then return the map.

**Constraints:**
- Use only OTP/stdlib — no external dependencies.
- Must work correctly when `worker_count` is greater than `length(items)`.
- `process_fn` may be slow or fast — faster workers should naturally pick up slack, which the metrics should make visible.

Give me the complete implementation in a single file.