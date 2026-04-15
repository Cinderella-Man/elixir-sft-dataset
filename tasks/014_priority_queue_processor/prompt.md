Write me an Elixir GenServer module called `PriorityQueue` that processes tasks based on priority levels, always picking the highest priority task available.

I need these functions in the public API:

- `PriorityQueue.start_link(opts)` to start the process. It should accept a `:name` option for process registration and a `:processor` option which is a single-arity function that will be called to "process" each task. If not provided, default to `fn task -> task end` (identity). The GenServer should process tasks one at a time asynchronously — after finishing one task, it immediately picks the next highest-priority one if any are queued.

- `PriorityQueue.enqueue(server, task, priority)` where priority is one of `:high`, `:normal`, or `:low`. This adds a task to the queue and triggers processing if the processor is currently idle. Return `:ok`.

- `PriorityQueue.status(server)` returning a map of pending task counts per priority level, like `%{high: 0, normal: 2, low: 1}`. This count should only include tasks that have not yet started processing.

- `PriorityQueue.drain(server)` which blocks until all currently enqueued tasks have been processed and the queue is empty. This is essential for testing. Return `:ok`.

The priority ordering is `:high` > `:normal` > `:low`. The GenServer must always pick the highest priority task available next. Within the same priority level, tasks must be processed in FIFO order (the order they were enqueued).

Processing should happen via internal message passing — when a task is enqueued and the processor is idle, the GenServer sends itself a `:process_next` message. When a task finishes processing, if more tasks remain, it sends itself another `:process_next` message. The processor function is called synchronously inside the GenServer's `handle_info` for `:process_next`.

Each processed task's result should be stored internally so tests can retrieve the processing history. Provide `PriorityQueue.processed(server)` which returns a list of `{task, result}` tuples in the order tasks were processed.

Give me the complete module in a single file. Use only OTP standard library, no external dependencies.