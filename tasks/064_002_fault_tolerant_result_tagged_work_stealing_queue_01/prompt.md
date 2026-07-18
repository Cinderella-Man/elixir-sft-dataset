Write me an Elixir module called `WorkStealQueue` that distributes work across N worker processes using a work-stealing algorithm, but with **fault-tolerant, result-tagged** semantics: the `process_fn` you hand it is allowed to blow up (raise, throw, or exit) on some items, and a single bad item must never take down a worker or lose any other item.

I need one primary public function:

- `WorkStealQueue.run(items, worker_count, process_fn)` — takes a list of items, a number of worker processes to spawn, and a one-arity function to apply to each item. Returns a list of `%{item: item, result: tagged_result, worker_id: non_neg_integer}` maps — exactly one per input item, in any order. `process_fn` is applied exactly once to each item (work-stealing must *move* items between workers, never copy them).

**Result tagging:**

- If `process_fn.(item)` returns normally with value `v`, the result field must be `{:ok, v}`. This includes ordinary values that happen to look like errors — e.g. `nil`, an `{:error, ...}` tuple, or an `{:exit, ...}` tuple returned (not raised/thrown/exited) are all tagged `{:ok, v}`.
- If `process_fn.(item)` **raises** an exception, the result field must be `{:error, %{kind: :error, reason: message}}` where `message` is the exception's message string.
- If `process_fn.(item)` **throws** a value `t`, the result field must be `{:error, %{kind: :throw, reason: t}}`.
- If `process_fn.(item)` **exits** with reason `r`, the result field must be `{:error, %{kind: :exit, reason: r}}`. This applies even when `r` is `:normal`.

A failure on one item must NOT prevent the owning worker from continuing with the rest of its queue, and must NOT prevent stealing.

**How it should work internally:**

1. Partition the input list as evenly as possible across `worker_count` workers. Each worker gets a local queue (a list it owns).
2. Spawn all workers as `Task`s. Each worker processes its local queue sequentially, wrapping every `process_fn` call so exceptions/throws/exits are captured and tagged (never propagated).
3. When a worker empties its local queue, it should *steal* work from the busiest worker (the one with the most items remaining). A steal only takes items when the victim has at least two items left: the thief takes the back half of the victim's queue (rounded down), leaving the front half — so a victim down to its last item is never robbed and always processes that item itself. If every other worker's queue is empty, the stealing worker simply exits.
4. Each worker must tag every result with its own `worker_id` (an integer from `0` to `worker_count - 1`).

**Coordination requirements:**

- Workers need a shared coordination mechanism (e.g. an `Agent` or `GenServer`) that tracks each worker's remaining queue so steal attempts can find the busiest worker atomically enough to avoid races. Occasional failed steals (victim emptied first) should be handled gracefully by retrying or moving on.
- `run/3` must be synchronous: block until every item has been processed (successfully or with a captured error) and then return the complete result list.

**Constraints:**
- Use only OTP/stdlib — no external dependencies.
- Must work correctly when `worker_count` is greater than `length(items)`.
- An empty `items` list returns `[]`.
- `process_fn` may be slow or fast — faster workers should naturally pick up slack.

Give me the complete implementation in a single file.
