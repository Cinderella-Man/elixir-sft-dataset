Write me an Elixir module called `RetryPool` that manages a pool of worker GenServers with a bounded task queue, per-task execution timeouts, and automatic retry on failure.

I need these functions in the public API:

- `RetryPool.start_link(opts)` to start the pool supervisor/manager. It should accept `:pool_size` (number of worker processes, default 3), `:max_queue` (maximum pending tasks in the queue, default 10), and `:name` option for process registration.

- `RetryPool.submit(pool, task_func, opts \\ [])` where `task_func` is a zero-arity function to execute. Options include `:task_timeout` (max milliseconds a single execution attempt may run, default 30_000) and `:max_retries` (number of retry attempts after the initial try, default 0 meaning no retries). If a worker is idle, dispatch immediately. If all workers are busy but the queue isn't full, enqueue it. If the queue is full, return `{:error, :queue_full}`. On success return `{:ok, ref}`.

- `RetryPool.await(pool, ref, timeout \\ 5_000)` which blocks the caller until the final result for `ref` is available or the timeout expires. Return `{:ok, result}` if the task completed successfully (on any attempt), `{:error, :timeout}` if the await timeout fires, `{:error, {:task_failed, reason, attempts}}` if the task exhausted all retries where `attempts` is the total number of attempts made, or `{:error, {:task_timeout, attempts}}` if the task timed out on its final attempt.

- `RetryPool.status(pool)` which returns a map with keys `:busy_workers`, `:idle_workers`, `:queue_length`, and `:retry_count` (cumulative number of retry attempts made since pool start).

Task timeout enforcement: when a worker has been executing a task for longer than `:task_timeout`, the pool must kill the worker, start a replacement, and either retry the task (if retries remain) or report failure to the awaiter. A timed-out task that still has retries remaining should be re-enqueued at the front of the queue (to preserve fairness — it already waited once).

Task crash handling: if a worker crashes (raises an exception) while executing a task, the same retry logic applies — retry if attempts remain, otherwise report `{:error, {:task_failed, reason, attempts}}`.

The queue is FIFO for new submissions. Retried tasks go to the front of the queue. When a worker finishes a task, it should automatically pull the next task from the queue if one is pending.

Workers must be supervised. The pool itself should remain fully functional after any worker crash or timeout.

Give me the complete implementation in a single file. Use only OTP standard library (GenServer, DynamicSupervisor, etc.), no external dependencies.