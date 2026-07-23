# Design Brief: `CancellablePool`

## Problem

We need an Elixir module called `CancellablePool` that manages a pool of worker GenServers backed by a bounded task queue, with support for cancelling tasks that are either waiting or already running. Deliver the complete implementation in a single file.

## Constraints

- Use only the OTP standard library (GenServer, DynamicSupervisor, etc.). No external dependencies.
- Tasks must execute in submission order — the queue is FIFO.
- When a worker finishes a task, it should automatically pull the next task from the queue if one is pending.
- Workers must be supervised. If a worker crashes mid-task (not via cancellation), the pool should start a replacement worker, the caller awaiting that task's ref should get `{:error, {:task_crashed, reason}}`, and any remaining queued tasks should not be lost. A task that raises an exception while running counts as such a crash. The pool itself should remain fully functional after a worker crash.
- When a running task is cancelled, the replacement worker should immediately pick up the next queued task if one exists.

## Required Interface

1. `CancellablePool.start_link(opts)` — starts the pool supervisor/manager. It should accept `:pool_size` (number of worker processes, default 3), `:max_queue` (maximum pending tasks in the queue, default 10), and `:name` option for process registration.

2. `CancellablePool.submit(pool, task_func)` — where `task_func` is a zero-arity function to execute. If a worker is idle, dispatch immediately. If all workers are busy but the queue isn't full, enqueue it. If the queue is full, return `{:error, :queue_full}`. On success return `{:ok, ref}` where `ref` is a unique reference the caller can use to retrieve the result later or cancel the task.

3. `CancellablePool.cancel(pool, ref)` — attempts to cancel a task identified by `ref`. If the task is still queued (pending), remove it from the queue and return `:ok` — the awaiter should receive `{:error, :cancelled}`. If the task is currently running on a worker, kill the worker, start a replacement, and return `:ok` — the awaiter should receive `{:error, :cancelled}`. If the ref is unknown (already completed, already cancelled, or never existed), return `{:error, :not_found}`.

4. `CancellablePool.await(pool, ref, timeout \\ 5_000)` — blocks the caller until the result for `ref` is available or the timeout expires. Return `{:ok, result}` if the task completed successfully, `{:error, :timeout}` if the timeout fires, `{:error, :cancelled}` if the task was cancelled, or `{:error, {:task_crashed, reason}}` if the worker crashed while executing that task. An unknown ref should simply block until the timeout and then return `{:error, :timeout}`.

5. `CancellablePool.status(pool)` — returns a map with keys `:busy_workers`, `:idle_workers`, `:queue_length`, and `:cancelled_count` (cumulative count of tasks cancelled since pool start).

## Acceptance Criteria

- `submit/2` dispatches to an idle worker immediately, enqueues when all workers are busy and the queue has room, and returns `{:error, :queue_full}` when the queue is full; successful submissions return `{:ok, ref}` with a unique `ref`.
- Queued tasks run in FIFO submission order, and a worker that finishes automatically pulls the next pending task from the queue.
- Cancelling a pending (queued) task removes it from the queue, returns `:ok`, and causes its awaiter to receive `{:error, :cancelled}`.
- Cancelling a running task kills the worker, starts a replacement, returns `:ok`, causes its awaiter to receive `{:error, :cancelled}`, and the replacement worker immediately picks up the next queued task if one exists.
- Cancelling an unknown ref (already completed, already cancelled, or never existed) returns `{:error, :not_found}`.
- `await/3` returns `{:ok, result}` on success, `{:error, :timeout}` on timeout, `{:error, :cancelled}` when cancelled, and `{:error, {:task_crashed, reason}}` when the worker crashed executing that task; an unknown ref blocks until the timeout and then returns `{:error, :timeout}`.
- On a mid-task worker crash (including a task that raises an exception), the pool starts a replacement worker, the awaiter of that task's ref gets `{:error, {:task_crashed, reason}}`, remaining queued tasks are preserved, and the pool remains fully functional.
- `status/1` returns a map with `:busy_workers`, `:idle_workers`, `:queue_length`, and `:cancelled_count` (cumulative count of tasks cancelled since pool start).
- The implementation is a single file using only the OTP standard library, with `:pool_size` defaulting to 3, `:max_queue` defaulting to 10, and a supported `:name` registration option.
