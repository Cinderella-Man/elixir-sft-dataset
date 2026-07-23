# Design Brief: `ConcurrentPriorityQueue`

## Problem

We need an Elixir GenServer module called `ConcurrentPriorityQueue` that processes tasks according to priority levels, with configurable concurrency — up to N tasks can be processed simultaneously.

## Constraints

- Deliver the complete module in a single file.
- Use only the OTP standard library; no external dependencies.
- Priority ordering is `:critical` > `:normal` > `:low`. The GenServer must always pick the highest priority task available next when a slot opens up. Within the same priority level, tasks must be started in FIFO order (the order they were enqueued).
- When a task finishes and there are more tasks queued, the GenServer immediately picks the next highest-priority task if a concurrency slot is available.
- Each task's `:processor` function must run inside its own separate spawned process (one process per task), and that process must terminate once the task's processing completes.
- The number of these worker processes running at once must never exceed `:max_concurrency`.
- The GenServer records the `{task, result}` pair once a task finishes, where `result` is the value the processor returned — including when the processor returns `nil` (that is still recorded as `{task, nil}`).

## Required Interface

1. `ConcurrentPriorityQueue.start_link(opts)` — starts the process. It should accept:
   - `:name` — option for process registration.
   - `:processor` — a single-arity function called to "process" each task. Default: `fn task -> task end`.
   - `:max_concurrency` — the maximum number of tasks that can be processed simultaneously (default `1`). Must be a positive integer, and `start_link/1` must validate it: a non-positive or non-integer value raises an `ArgumentError` (it must not return an error tuple or exit).

2. `ConcurrentPriorityQueue.enqueue(server, task, priority)` — where priority is one of `:critical`, `:normal`, or `:low`. This adds a task to the queue and triggers processing if there is an available concurrency slot. Return `:ok`.

3. `ConcurrentPriorityQueue.status(server)` — returns a map with exactly the keys `:critical`, `:normal`, `:low`, `:active`, and `:max_concurrency` — the pending task counts per priority level, the number of currently active (in-progress) tasks, and the max concurrency setting. Example: `%{critical: 0, normal: 2, low: 1, active: 3, max_concurrency: 5}`. Pending counts should only include tasks that have not yet started processing.

4. `ConcurrentPriorityQueue.drain(server)` — blocks until all currently enqueued tasks have been processed and the queue is empty and no tasks are actively being processed. Return `:ok`. Calling `drain/1` on an already-empty, idle queue must return `:ok` immediately.

5. `ConcurrentPriorityQueue.processed(server)` — returns a list of `{task, result}` tuples in the order tasks finished processing (an empty list when nothing has been processed). Note: with concurrency > 1, the completion order may differ from the start order.

## Acceptance Criteria

- The public API exposes exactly the five functions above with the described behavior.
- Concurrency is honored: at most `:max_concurrency` worker processes run at any moment, and a freed slot is immediately filled by the next highest-priority, FIFO-within-priority task.
- `start_link/1` raises `ArgumentError` for a non-positive or non-integer `:max_concurrency`, rather than returning an error tuple or exiting.
- `status/1` returns a map whose keys are exactly `:critical`, `:normal`, `:low`, `:active`, and `:max_concurrency`, with pending counts excluding tasks that have already started processing.
- `drain/1` returns `:ok` after the queue is empty and no tasks are active, and returns `:ok` immediately on an already-empty, idle queue.
- `processed/1` reports `{task, result}` tuples in completion order, including `{task, nil}` when the processor returned `nil`.
- Each task runs in its own spawned process that terminates on completion, using only the OTP standard library, delivered as one complete module file.
