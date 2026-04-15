Write me an Elixir module called `WorkStealQueue` that distributes work across N worker processes using a work-stealing algorithm.

I need one primary public function:

- `WorkStealQueue.run(items, worker_count, process_fn)` — takes a list of items, a number of worker processes to spawn, and a one-arity function to apply to each item. Returns a list of `%{item: item, result: term, worker_id: non_neg_integer}` maps — one per input item, in any order.

**How it should work internally:**

1. Partition the input list as evenly as possible across `worker_count` workers. Each worker gets a local queue (a list it owns).
2. Spawn all workers as `Task`s or plain processes. Each worker processes its local queue sequentially using `process_fn`.
3. When a worker empties its local queue, it should *steal* work from the busiest worker (the one with the most items remaining). Stealing takes items from the back half of the victim's queue. If no other worker has any remaining work, the stealing worker simply exits.
4. Each worker must tag every result with its own `worker_id` (an integer from `0` to `worker_count - 1`) so callers can verify which worker processed which item.

**Coordination requirements:**

- Workers need a shared coordination mechanism (e.g. an `Agent` or `GenServer`) that tracks each worker's remaining queue so that steal attempts can find the busiest worker atomically enough to avoid races. You may accept occasional failed steals (the victim emptied before the steal completed) — just handle that case gracefully by retrying or moving on.
- The function must be synchronous: `run/3` should block until every item has been processed and then return the complete result list.

**Constraints:**
- Use only OTP/stdlib — no external dependencies.
- The solution should work correctly when `worker_count` is greater than `length(items)` (some workers get empty queues from the start).
- `process_fn` may be slow or fast — the algorithm should naturally cause faster workers to pick up slack from slower ones.

Give me the complete implementation in a single file.