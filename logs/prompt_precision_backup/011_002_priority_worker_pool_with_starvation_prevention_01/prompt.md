Write me an Elixir module called `PriorityWorkerPool` that manages a pool of worker GenServers with a priority-based bounded task queue and starvation prevention.

I need these functions in the public API:

- `PriorityWorkerPool.start_link(opts)` to start the pool supervisor/manager. It should accept `:pool_size` (number of worker processes, default 3), `:max_queue` (maximum pending tasks across all priorities, default 10), `:promote_after_ms` (time after which a waiting task's priority is promoted one level to prevent starvation, default 5_000), and `:name` option for process registration.

- `PriorityWorkerPool.submit(pool, task_func, priority \\ :normal)` where `task_func` is a zero-arity function and `priority` is one of `:high`, `:normal`, or `:low`. If a worker is idle, dispatch immediately (regardless of priority since no one is waiting). If all workers are busy but the queue isn't full, enqueue it at the appropriate priority level. If the queue is full, return `{:error, :queue_full}`. On success return `{:ok, ref}` where `ref` is a unique reference.

- `PriorityWorkerPool.await(pool, ref, timeout \\ 5_000)` which blocks the caller until the result for `ref` is available or the timeout expires. Return `{:ok, result}` if the task completed successfully, `{:error, :timeout}` if the timeout fires before the result is ready, or `{:error, {:task_crashed, reason}}` if the worker crashed while executing that task.

- `PriorityWorkerPool.status(pool)` which returns a map with keys `:busy_workers`, `:idle_workers`, `:queue_high`, `:queue_normal`, `:queue_low`, and `:total_queue_length` for introspection.

The queue must be ordered by priority: high tasks are always dequeued before normal, and normal before low. Within the same priority level, tasks are FIFO. When a worker finishes a task, it should automatically pull the next highest-priority task from the queue.

Starvation prevention: the pool runs a periodic check (every `:promote_after_ms` milliseconds). Any task that has been waiting in the queue longer than `:promote_after_ms` gets promoted one priority level (low → normal, normal → high, high stays high). This ensures low-priority tasks eventually execute even under sustained high-priority load.

Workers must be supervised. If a worker crashes mid-task, the pool should start a replacement worker, the caller awaiting that task's ref should get `{:error, {:task_crashed, reason}}`, and any remaining queued tasks should not be lost. The pool itself should remain fully functional after a worker crash.

Give me the complete implementation in a single file. Use only OTP standard library (GenServer, DynamicSupervisor, etc.), no external dependencies.