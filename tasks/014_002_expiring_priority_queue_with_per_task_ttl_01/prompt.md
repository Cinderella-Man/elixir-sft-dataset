# Design Brief: `ExpiringPriorityQueue`

## Problem & Context

We need an Elixir GenServer module called `ExpiringPriorityQueue` that processes tasks based on priority levels, but also supports per-task TTL (time-to-live) so that stale tasks are skipped rather than processed.

## Constraints

- Deliver the complete module in a single file.
- Use only OTP standard library, no external dependencies.
- The GenServer must process tasks one at a time asynchronously — after finishing one task, it immediately picks the next highest-priority non-expired one if any are queued.
- While a task is being processed the server must stay responsive to `enqueue`, `status`, `processed`, `expired` and `drain` calls.
- The priority ordering is `:high` > `:normal` > `:low`. The GenServer must always pick the highest priority task available next. Within the same priority level, tasks must be processed in FIFO order (the order they were enqueued).
- Processing must happen via internal message passing — when a task is enqueued and the processor is idle, the GenServer sends itself a `:process_next` message. When a task finishes processing, if more tasks remain, it sends itself another `:process_next` message. The processor function is called synchronously inside a spawned process from `handle_info` for `:process_next`, so the GenServer's own loop is never blocked while a task runs.
- When the GenServer picks the next task to process via `:process_next`, it should check the task's expiration time against the current time. A task counts as expired the instant the current time reaches or passes its expiration time (`now >= expires_at`) — so a task whose expiry equals the current clock is treated as expired, not pending, and a task enqueued with `ttl_ms: 0` expires immediately. If the task has expired, it should be added to the expired list, skipped, and the GenServer should immediately try the next task. This means a single `:process_next` might skip multiple expired tasks before finding a valid one (or finding the queue empty).
- Use the configured `:clock` function for all TTL calculations to make testing deterministic.

## Required Interface

The public API must expose exactly these functions:

1. `ExpiringPriorityQueue.start_link(opts)` to start the process. It should accept a `:name` option for process registration and a `:processor` option which is a single-arity function that will be called to "process" each task. If not provided, default to `fn task -> task end` (identity). It should also accept `:default_ttl_ms` (default `5000`) which is the TTL applied to tasks that don't specify their own. It should accept a `:clock` option — a zero-arity function returning the current time in milliseconds (default `fn -> System.monotonic_time(:millisecond) end`).

2. `ExpiringPriorityQueue.enqueue(server, task, priority, opts \\ [])` where priority is one of `:high`, `:normal`, or `:low`. Guard this argument so that any other value (including a non-atom such as `"high"`) raises a `FunctionClauseError` from `enqueue` itself before the server is touched. Accepts an optional `:ttl_ms` in opts to override the default TTL for this specific task. The TTL countdown starts from the moment of enqueue, so a task enqueued when the clock reads `t` with an effective TTL of `ttl` expires at `t + ttl`. This adds a task to the queue and triggers processing if the processor is currently idle. Return `:ok`.

3. `ExpiringPriorityQueue.status(server)` returning a map with pending task counts per priority level and the count of expired tasks, exactly like `%{high: 0, normal: 2, low: 1, expired: 3}` (those four keys and no others). Pending counts should only include non-expired tasks that have not yet started processing; a task counts as pending only while the current time is strictly before its expiration (`now < expires_at`). The `expired` value is the total number of tasks recorded as expired so far.

4. `ExpiringPriorityQueue.drain(server)` which blocks until all currently enqueued tasks have been processed (or expired) and the queue is empty. On an already-idle, empty queue it returns immediately. This is essential for testing. Return `:ok`.

5. `ExpiringPriorityQueue.processed(server)` which returns a list of `{task, result}` tuples — where `result` is the value the processor function returned for that task — in the order tasks were processed (only successfully processed tasks, not expired ones).

6. `ExpiringPriorityQueue.expired(server)` which returns a list of `{task, priority}` tuples for tasks that were skipped due to expiration, in the order they were discovered as expired.

## Acceptance Criteria

- The GenServer processes tasks one at a time asynchronously, immediately picking the next highest-priority non-expired task after finishing one, and remains responsive to `enqueue`, `status`, `processed`, `expired`, and `drain` while a task is being processed.
- `start_link/1` honors `:name`, `:processor` (defaulting to `fn task -> task end`), `:default_ttl_ms` (defaulting to `5000`), and `:clock` (defaulting to `fn -> System.monotonic_time(:millisecond) end`), using that clock for all TTL calculations.
- `enqueue/4` guards `priority` to `:high`, `:normal`, or `:low`, raising `FunctionClauseError` from `enqueue` itself (before touching the server) on any other value including a non-atom such as `"high"`; honors `:ttl_ms` overriding `:default_ttl_ms`; sets expiration to `t + ttl` from the enqueue-time clock reading `t`; triggers processing when idle; and returns `:ok`.
- `status/1` returns a map with exactly the keys `high`, `normal`, `low`, and `expired`, e.g. `%{high: 0, normal: 2, low: 1, expired: 3}`, counting a task as pending only while `now < expires_at` and reporting the total number of expired tasks so far.
- `drain/1` blocks until the queue is empty (all tasks processed or expired), returns immediately on an already-idle empty queue, and returns `:ok`.
- `processed/1` returns `{task, result}` tuples for successfully processed tasks only, in processing order, with `result` being the processor's return value.
- `expired/1` returns `{task, priority}` tuples for tasks skipped due to expiration, in the order they were discovered as expired.
- Task selection always picks the highest priority available (`:high` > `:normal` > `:low`), FIFO within the same priority.
- A task is expired the instant `now >= expires_at` (equal-to-clock and `ttl_ms: 0` expire immediately); expired tasks are recorded, skipped, and the next task is tried immediately, so one `:process_next` may skip multiple expired tasks before finding a valid one or an empty queue.
- Processing uses internal `:process_next` message passing: enqueue-while-idle sends `:process_next`; task completion with remaining tasks sends another `:process_next`; the processor runs synchronously inside a process spawned from `handle_info` for `:process_next` so the GenServer loop is never blocked.
- The deliverable is the complete module in a single file using only the OTP standard library with no external dependencies.
