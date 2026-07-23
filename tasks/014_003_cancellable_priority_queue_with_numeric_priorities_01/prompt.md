# Ticket: `CancellablePriorityQueue` — GenServer priority queue with cancellation

Implement an Elixir GenServer module named `CancellablePriorityQueue` that processes tasks by numeric priority level and supports cancelling pending tasks by reference. Deliver the complete module in a single file. Use only the OTP standard library — no external dependencies.

**Startup — `CancellablePriorityQueue.start_link(opts)`**
- Starts the process.
- Accepts a `:name` option for process registration.
- Accepts a `:processor` option: a single-arity function called to "process" each task; if not provided, default to `fn task -> task end` (identity).
- Processes tasks one at a time asynchronously — after finishing one task, immediately picks the next highest-priority one if any are queued.

**Enqueue — `CancellablePriorityQueue.enqueue(server, task, priority)`**
- `priority` is a non-negative integer; lower number = higher priority (like Unix nice values). Priority `0` is the highest.
- Adds a task to the queue and triggers processing if the processor is currently idle.
- Returns `{:ok, ref}` where `ref` is a unique reference (use `make_ref()`) usable to cancel the task later.

**Cancel — `CancellablePriorityQueue.cancel(server, ref)`**
- Attempts to cancel a pending (not-yet-started) task identified by `ref`.
- Returns `:ok` if the task was found and removed from the queue.
- Returns `{:error, :not_found}` if the ref doesn't match any pending task (already processed, already cancelled, or never existed).
- A task currently being processed cannot be cancelled; such a call also returns `{:error, :not_found}`.

**Status — `CancellablePriorityQueue.status(server)`**
- Returns a map with the total pending count, a breakdown of pending counts per priority level, and the count of cancelled tasks. Example: `%{pending: 5, by_priority: %{0 => 2, 1 => 1, 5 => 2}, cancelled: 3}`.
- Only include priority levels that have pending tasks in `by_priority`; an empty queue reports `by_priority: %{}`.

**Drain — `CancellablePriorityQueue.drain(server)`**
- Blocks until all currently enqueued tasks have been processed and the queue is empty. Essential for testing.
- Returns `:ok`.

**Processed — `CancellablePriorityQueue.processed(server)`**
- Returns a list of `{task, result}` tuples in the order tasks were processed.

**Peek — `CancellablePriorityQueue.peek(server)`**
- Returns `{:ok, task, priority}` for the next task that would be processed (the highest-priority task at the front of its queue), without removing it.
- Returns `:empty` if the queue is empty.

**Priority ordering**
- Numeric: `0` is highest, then `1`, then `2`, etc. Always pick the lowest-numbered priority task available next.
- Within the same priority level, process tasks in FIFO order (the order they were enqueued).

**Internal storage**
- Use a map of `priority_number => :queue.new()` to store tasks, creating new queue entries dynamically as new priority levels are seen.
- Each queue entry should be `{ref, task}` so tasks can be identified for cancellation.

**Processing mechanism**
- Use internal message passing: when a task is enqueued and the processor is idle, the GenServer sends itself a `:process_next` message.
- When a task finishes processing, if more tasks remain, it sends itself another `:process_next` message.
- The processor function is called synchronously inside a spawned process from `handle_info` for `:process_next`.
