Write me an Elixir GenServer module called `ExpiringPriorityQueue` that processes tasks based on priority levels, but also supports per-task TTL (time-to-live) so that stale tasks are skipped rather than processed.

I need these functions in the public API:

- `ExpiringPriorityQueue.start_link(opts)` to start the process. It should accept a `:name` option for process registration and a `:processor` option which is a single-arity function that will be called to "process" each task. If not provided, default to `fn task -> task end` (identity). It should also accept `:default_ttl_ms` (default `5000`) which is the TTL applied to tasks that don't specify their own. The GenServer should process tasks one at a time asynchronously — after finishing one task, it immediately picks the next highest-priority non-expired one if any are queued.

- `ExpiringPriorityQueue.enqueue(server, task, priority, opts \\ [])` where priority is one of `:high`, `:normal`, or `:low`. Accepts an optional `:ttl_ms` in opts to override the default TTL for this specific task. The TTL countdown starts from the moment of enqueue. This adds a task to the queue and triggers processing if the processor is currently idle. Return `:ok`.

- `ExpiringPriorityQueue.status(server)` returning a map with pending task counts per priority level and the count of expired tasks, like `%{high: 0, normal: 2, low: 1, expired: 3}`. Pending counts should only include non-expired tasks that have not yet started processing.

- `ExpiringPriorityQueue.drain(server)` which blocks until all currently enqueued tasks have been processed (or expired) and the queue is empty. This is essential for testing. Return `:ok`.

- `ExpiringPriorityQueue.processed(server)` which returns a list of `{task, result}` tuples in the order tasks were processed (only successfully processed tasks, not expired ones).

- `ExpiringPriorityQueue.expired(server)` which returns a list of `{task, priority}` tuples for tasks that were skipped due to expiration, in the order they were discovered as expired.

The priority ordering is `:high` > `:normal` > `:low`. The GenServer must always pick the highest priority task available next. Within the same priority level, tasks must be processed in FIFO order (the order they were enqueued).

When the GenServer picks the next task to process via `:process_next`, it should check the task's expiration time against the current time. If the task has expired, it should be added to the expired list, skipped, and the GenServer should immediately try the next task. This means a single `:process_next` might skip multiple expired tasks before finding a valid one (or finding the queue empty).

Processing should happen via internal message passing — when a task is enqueued and the processor is idle, the GenServer sends itself a `:process_next` message. When a task finishes processing, if more tasks remain, it sends itself another `:process_next` message. The processor function is called synchronously inside a spawned process from `handle_info` for `:process_next`.

The GenServer should accept a `:clock` option in `start_link` — a zero-arity function returning the current time in milliseconds (default `fn -> System.monotonic_time(:millisecond) end`). Use this clock for all TTL calculations to make testing deterministic.

Give me the complete module in a single file. Use only OTP standard library, no external dependencies.