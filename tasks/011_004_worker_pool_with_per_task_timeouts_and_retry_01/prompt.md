Hey — I need you to write me an Elixir module called `RetryPool` that manages a pool of worker GenServers with a bounded task queue, per-task execution timeouts, and automatic retry on failure. I'd like the complete implementation in a single file, using only the OTP standard library (GenServer, DynamicSupervisor, etc.) — no external dependencies, please.

Here's the public API I'm after. First, `RetryPool.start_link(opts)` to start the pool supervisor/manager. It should accept `:pool_size` (number of worker processes, default 3), `:max_queue` (maximum pending tasks in the queue, default 10), and a `:name` option for process registration.

Next, `RetryPool.submit(pool, task_func, opts \\ [])`, where `task_func` is a zero-arity function to execute. Its options include `:task_timeout` (max milliseconds a single execution attempt may run, default 30_000) and `:max_retries` (number of retry attempts after the initial try, default 0 meaning no retries). The dispatch logic I want: if a worker is idle, dispatch immediately; if all workers are busy but the queue isn't full, enqueue it; if the queue is full, return `{:error, :queue_full}`. On success return `{:ok, ref}`.

Then `RetryPool.await(pool, ref, timeout \\ 5_000)`, which blocks the caller until the final result for `ref` is available or the timeout expires. It should return `{:ok, result}` if the task completed successfully (on any attempt), `{:error, :timeout}` if the await timeout fires, `{:error, {:task_failed, reason, attempts}}` if the task exhausted all retries where `attempts` is the total number of attempts made, or `{:error, {:task_timeout, attempts}}` if the task timed out on its final attempt (again `attempts` is the total number of attempts made). One important detail: `await` must be called from the same process that called `submit` for that `ref` — results are delivered as plain messages to the submitter's mailbox, so any other process awaiting the ref just times out.

Finally, `RetryPool.status(pool)`, which returns a map whose values are all non-negative integers, with keys `:busy_workers` (count of workers currently executing a task), `:idle_workers` (count of workers waiting for work), `:queue_length` (number of pending tasks in the queue), and `:retry_count` (cumulative number of retry attempts made since pool start).

On task timeout enforcement: when a worker has been executing a task for longer than `:task_timeout`, the pool must kill the worker, start a replacement, and either retry the task (if retries remain) or report failure to the awaiter. A timed-out task that still has retries remaining should be re-enqueued at the front of the queue (to preserve fairness — it already waited once).

For task crash handling: if a worker crashes (raises an exception) while executing a task, the same retry logic applies — retry if attempts remain, otherwise report `{:error, {:task_failed, reason, attempts}}`.

A couple of queue semantics to keep straight: the queue is FIFO for new submissions, retried tasks go to the front of the queue, and when a worker finishes a task it should automatically pull the next task from the queue if one is pending.

Workers must be supervised, and the pool itself should remain fully functional after any worker crash or timeout.
