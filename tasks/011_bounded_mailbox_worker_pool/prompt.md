Write me an Elixir module called `WorkerPool` that manages a pool of worker GenServers with a bounded task queue.

I need these functions in the public API:

- `WorkerPool.start_link(opts)` to start the pool supervisor/manager. It should accept `:pool_size` (number of worker processes, default 3), `:max_queue` (maximum pending tasks in the queue, default 10), and `:name` option for process registration.

- `WorkerPool.submit(pool, task_func)` where `task_func` is a zero-arity function to execute. If a worker is idle, dispatch immediately. If all workers are busy but the queue isn't full, enqueue it. If the queue is full, return `{:error, :queue_full}`. On success return `{:ok, ref}` where `ref` is a unique reference the caller can use to retrieve the result later.

- `WorkerPool.await(pool, ref, timeout \\ 5_000)` which blocks the caller until the result for `ref` is available or the timeout expires. Return `{:ok, result}` if the task completed successfully, `{:error, :timeout}` if the timeout fires before the result is ready, or `{:error, {:task_crashed, reason}}` if the worker crashed while executing that task.

- `WorkerPool.status(pool)` which returns a map with keys `:busy_workers`, `:idle_workers`, and `:queue_length` for introspection.

Tasks must execute in submission order — the queue is FIFO. When a worker finishes a task, it should automatically pull the next task from the queue if one is pending.

Workers must be supervised. If a worker crashes mid-task, the pool should start a replacement worker, the caller awaiting that task's ref should get `{:error, {:task_crashed, reason}}`, and any remaining queued tasks should not be lost. The pool itself should remain fully functional after a worker crash.

Give me the complete implementation in a single file. Use only OTP standard library (GenServer, DynamicSupervisor, etc.), no external dependencies. Structure it however makes sense — a top-level module with internal child modules is fine.