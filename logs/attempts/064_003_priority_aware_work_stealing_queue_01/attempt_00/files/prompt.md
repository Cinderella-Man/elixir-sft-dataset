Write me an Elixir module called `WorkStealQueue` that distributes **prioritized** work across N worker processes using a work-stealing algorithm. Higher-priority work should be done first within each worker, and when an idle worker steals, it should take the *least urgent* work off a busy peer — leaving the busy worker to keep grinding on its most urgent items.

I need one primary public function:

- `WorkStealQueue.run(items, worker_count, process_fn)` — `items` is a list of `{priority, payload}` tuples where `priority` is an integer (higher = more urgent). `worker_count` is the number of workers to spawn. `process_fn` is a one-arity function applied to each **payload**. Returns a list of `%{item: payload, priority: priority, result: term, worker_id: non_neg_integer}` maps — one per input tuple, in any order.

**How it should work internally:**

1. Partition the input list as evenly as possible across `worker_count` workers. Each worker owns a local priority queue kept sorted so the highest-priority item is always next.
2. Spawn all workers as `Task`s. Each worker repeatedly pops and processes its **highest-priority** local item, applying `process_fn` to the payload.
3. When a worker empties its local queue, it *steals* from the busiest worker (the one with the most items remaining). Stealing takes the **lowest-priority half** of the victim's queue (the back of its sorted queue), so the victim retains its most urgent work. If no other worker has any remaining work, the stealing worker simply exits.
4. Each worker tags every result with its own `worker_id` (`0` to `worker_count - 1`) and echoes back the item's `priority`.

**Coordination requirements:**

- Use a shared coordination mechanism (e.g. an `Agent` or `GenServer`) tracking each worker's remaining sorted queue so steal attempts can find the busiest worker and slice off its lowest-priority items atomically. Failed steals (victim emptied first) should be handled gracefully by retrying or moving on.
- `run/3` must be synchronous: block until every item is processed, then return the full result list.

**Constraints:**
- Use only OTP/stdlib — no external dependencies.
- Must work correctly when `worker_count` is greater than `length(items)`.
- Within a single worker, items must be processed in strictly descending priority order.
- `process_fn` may be slow or fast — faster workers should naturally pick up the low-priority slack.

Give me the complete implementation in a single file.