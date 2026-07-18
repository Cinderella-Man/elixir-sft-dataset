Write me an Elixir GenServer module called `ConcurrentPriorityQueue` that processes tasks based on priority levels with configurable concurrency — up to N tasks can be processed simultaneously.

I need these functions in the public API:

- `ConcurrentPriorityQueue.start_link(opts)` to start the process. It should accept:
  - `:name` — option for process registration
  - `:processor` — a single-arity function called to "process" each task. Default: `fn task -> task end`
  - `:max_concurrency` — the maximum number of tasks that can be processed simultaneously (default `1`). Must be a positive integer, and `start_link/1` must validate it: a non-positive or non-integer value raises an `ArgumentError` (it must not return an error tuple or exit).

  When a task finishes and there are more tasks queued, the GenServer immediately picks the next highest-priority task if a concurrency slot is available.

- `ConcurrentPriorityQueue.enqueue(server, task, priority)` where priority is one of `:critical`, `:normal`, or `:low`. This adds a task to the queue and triggers processing if there is an available concurrency slot. Return `:ok`.

- `ConcurrentPriorityQueue.status(server)` returning a map with exactly the keys `:critical`, `:normal`, `:low`, `:active`, and `:max_concurrency` — the pending task counts per priority level, the number of currently active (in-progress) tasks, and the max concurrency setting. Example: `%{critical: 0, normal: 2, low: 1, active: 3, max_concurrency: 5}`. Pending counts should only include tasks that have not yet started processing.

- `ConcurrentPriorityQueue.drain(server)` which blocks until all currently enqueued tasks have been processed and the queue is empty and no tasks are actively being processed. Return `:ok`. Calling `drain/1` on an already-empty, idle queue must return `:ok` immediately.

- `ConcurrentPriorityQueue.processed(server)` which returns a list of `{task, result}` tuples in the order tasks finished processing (an empty list when nothing has been processed). Note: with concurrency > 1, the completion order may differ from the start order.

The priority ordering is `:critical` > `:normal` > `:low`. The GenServer must always pick the highest priority task available next when a slot opens up. Within the same priority level, tasks must be started in FIFO order (the order they were enqueued).

Each task's `:processor` function must run inside its own separate spawned process (one process per task), and that process must terminate once the task's processing completes. The number of these worker processes running at once must never exceed `:max_concurrency`. The GenServer records the `{task, result}` pair once a task finishes, where `result` is the value the processor returned — including when the processor returns `nil` (that is still recorded as `{task, nil}`).

Give me the complete module in a single file. Use only OTP standard library, no external dependencies.
