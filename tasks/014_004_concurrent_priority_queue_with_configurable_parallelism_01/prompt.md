Write me an Elixir GenServer module called `ConcurrentPriorityQueue` that processes tasks based on priority levels with configurable concurrency — up to N tasks can be processed simultaneously.

I need these functions in the public API:

- `ConcurrentPriorityQueue.start_link(opts)` to start the process. It should accept:
  - `:name` — option for process registration
  - `:processor` — a single-arity function called to "process" each task. Default: `fn task -> task end`
  - `:max_concurrency` — the maximum number of tasks that can be processed simultaneously (default `1`). Must be a positive integer.

  When a task finishes and there are more tasks queued, the GenServer immediately picks the next highest-priority task if a concurrency slot is available.

- `ConcurrentPriorityQueue.enqueue(server, task, priority)` where priority is one of `:critical`, `:normal`, or `:low`. This adds a task to the queue and triggers processing if there is an available concurrency slot. Return `:ok`.

- `ConcurrentPriorityQueue.status(server)` returning a map of pending task counts per priority level, the number of currently active (in-progress) tasks, and the max concurrency setting. Example: `%{critical: 0, normal: 2, low: 1, active: 3, max_concurrency: 5}`. Pending counts should only include tasks that have not yet started processing.

- `ConcurrentPriorityQueue.drain(server)` which blocks until all currently enqueued tasks have been processed and the queue is empty and no tasks are actively being processed. Return `:ok`.

- `ConcurrentPriorityQueue.processed(server)` which returns a list of `{task, result}` tuples in the order tasks finished processing. Note: with concurrency > 1, the completion order may differ from the start order.

The priority ordering is `:critical` > `:normal` > `:low`. The GenServer must always pick the highest priority task available next when a slot opens up. Within the same priority level, tasks must be started in FIFO order (the order they were enqueued).

Processing should happen via internal message passing. When a task is enqueued and there are available slots (`active_count < max_concurrency`), the GenServer sends itself a `:process_next` message. The processor function runs inside a spawned+monitored process. When a worker finishes (detected via `{:DOWN, ...}` message), if more tasks remain and a slot is available, the GenServer sends itself another `:process_next` message.

The GenServer should track active workers in a map of `{pid, monitor_ref} => task` so it can associate finished workers with their tasks. When a worker sends back its result and then exits, the GenServer records the `{task, result}` pair.

Give me the complete module in a single file. Use only OTP standard library, no external dependencies.