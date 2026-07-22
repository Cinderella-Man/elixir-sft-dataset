Write me an Elixir GenServer module called `CancellablePriorityQueue` that processes tasks based on numeric priority levels and supports cancelling pending tasks by reference.

I need these functions in the public API:

- `CancellablePriorityQueue.start_link(opts)` to start the process. It should accept a `:name` option for process registration and a `:processor` option which is a single-arity function that will be called to "process" each task. If not provided, default to `fn task -> task end` (identity). The GenServer should process tasks one at a time asynchronously — after finishing one task, it immediately picks the next highest-priority one if any are queued.

- `CancellablePriorityQueue.enqueue(server, task, priority)` where priority is a non-negative integer (lower number = higher priority, like Unix nice values). Priority `0` is the highest. This adds a task to the queue and triggers processing if the processor is currently idle. Return `{:ok, ref}` where `ref` is a unique reference (use `make_ref()`) that can be used to cancel the task later.

- `CancellablePriorityQueue.cancel(server, ref)` which attempts to cancel a pending (not-yet-started) task identified by `ref`. Returns `:ok` if the task was found and removed from the queue, or `{:error, :not_found}` if the ref doesn't match any pending task (either it was already processed, already cancelled, or never existed). You cannot cancel a task that is currently being processed.

- `CancellablePriorityQueue.status(server)` returning a map with the total pending count, a breakdown of pending counts per priority level, and the count of cancelled tasks. For example: `%{pending: 5, by_priority: %{0 => 2, 1 => 1, 5 => 2}, cancelled: 3}`. Only include priority levels that have pending tasks in the `by_priority` map.

- `CancellablePriorityQueue.drain(server)` which blocks until all currently enqueued tasks have been processed and the queue is empty. This is essential for testing. Return `:ok`.

- `CancellablePriorityQueue.processed(server)` which returns a list of `{task, result}` tuples in the order tasks were processed.

- `CancellablePriorityQueue.peek(server)` which returns `{:ok, task, priority}` for the next task that would be processed (the highest-priority task at the front of its queue), without removing it. Returns `:empty` if the queue is empty.

The priority ordering is numeric: `0` is highest priority, then `1`, then `2`, etc. The GenServer must always pick the lowest-numbered priority task available next. Within the same priority level, tasks must be processed in FIFO order (the order they were enqueued).

Internally, use a map of `priority_number => :queue.new()` to store tasks, creating new queue entries dynamically as new priority levels are seen. Each queue entry should be `{ref, task}` so tasks can be identified for cancellation.

Processing should happen via internal message passing — when a task is enqueued and the processor is idle, the GenServer sends itself a `:process_next` message. When a task finishes processing, if more tasks remain, it sends itself another `:process_next` message. The processor function is called synchronously inside a spawned process from `handle_info` for `:process_next`.

Give me the complete module in a single file. Use only OTP standard library, no external dependencies.