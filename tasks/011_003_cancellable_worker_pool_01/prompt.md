Write me an Elixir module called `CancellablePool` that manages a pool of worker GenServers with a bounded task queue and support for task cancellation.

I need these functions in the public API:

- `CancellablePool.start_link(opts)` to start the pool supervisor/manager. It should accept `:pool_size` (number of worker processes, default 3), `:max_queue` (maximum pending tasks in the queue, default 10), and `:name` option for process registration.

- `CancellablePool.submit(pool, task_func)` where `task_func` is a zero-arity function to execute. If a worker is idle, dispatch immediately. If all workers are busy but the queue isn't full, enqueue it. If the queue is full, return `{:error, :queue_full}`. On success return `{:ok, ref}` where `ref` is a unique reference the caller can use to retrieve the result later or cancel the task.

- `CancellablePool.cancel(pool, ref)` which attempts to cancel a task identified by `ref`. If the task is still queued (pending), remove it from the queue and return `:ok` — the awaiter should receive `{:error, :cancelled}`. If the task is currently running on a worker, kill the worker, start a replacement, and return `:ok` — the awaiter should receive `{:error, :cancelled}`. If the ref is unknown (already completed, already cancelled, or never existed), return `{:error, :not_found}`.

- `CancellablePool.await(pool, ref, timeout \\ 5_000)` which blocks the caller until the result for `ref` is available or the timeout expires. Return `{:ok, result}` if the task completed successfully, `{:error, :timeout}` if the timeout fires, `{:error, :cancelled}` if the task was cancelled, or `{:error, {:task_crashed, reason}}` if the worker crashed while executing that task.

- `CancellablePool.status(pool)` which returns a map with keys `:busy_workers`, `:idle_workers`, `:queue_length`, and `:cancelled_count` (cumulative count of tasks cancelled since pool start).

Tasks must execute in submission order — the queue is FIFO. When a worker finishes a task, it should automatically pull the next task from the queue if one is pending.

Workers must be supervised. If a worker crashes mid-task (not via cancellation), the pool should start a replacement worker, the caller awaiting that task's ref should get `{:error, {:task_crashed, reason}}`, and any remaining queued tasks should not be lost. The pool itself should remain fully functional after a worker crash.

When a running task is cancelled, the replacement worker should immediately pick up the next queued task if one exists.

Give me the complete implementation in a single file. Use only OTP standard library (GenServer, DynamicSupervisor, etc.), no external dependencies.