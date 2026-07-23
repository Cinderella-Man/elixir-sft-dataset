# Design Brief: `PriorityQueue` — a priority-ordered task processor

## Problem

We need an Elixir GenServer module called `PriorityQueue` that processes tasks based on priority levels, always picking the highest priority task available. Tasks are processed one at a time asynchronously — after finishing one task, the process immediately picks the next highest-priority one if any are queued.

## Constraints

- Use only OTP standard library, no external dependencies.
- The priority ordering is `:high` > `:normal` > `:low`. The GenServer must always pick the highest priority task available next.
- Within the same priority level, tasks must be processed in FIFO order (the order they were enqueued).
- Processing must happen via internal message passing:
  - When a task is enqueued and the processor is idle, the GenServer sends itself a `:process_next` message.
  - When a task finishes processing, if more tasks remain, it sends itself another `:process_next` message.
  - The `handle_info` for `:process_next` dequeues the highest-priority task and runs the processor function in a separate spawned, monitored process (e.g. via `spawn_monitor/1`) — never inline in the GenServer loop — so that `enqueue`, `status`, and `drain` calls remain responsive even while a long-running or blocking task is being processed. When the spawned process finishes, the GenServer records the result and moves on.
- Each processed task's result must be stored internally so tests can retrieve the processing history.
- Deliver the complete module in a single file.

## Required interface

1. `PriorityQueue.start_link(opts)` — starts the process. It should accept a `:name` option for process registration and a `:processor` option which is a single-arity function that will be called to "process" each task. If not provided, `:processor` defaults to `fn task -> task end` (identity).

2. `PriorityQueue.enqueue(server, task, priority)` — where `priority` is one of `:high`, `:normal`, or `:low`. This adds a task to the queue and triggers processing if the processor is currently idle. Returns `:ok`.

3. `PriorityQueue.status(server)` — returns a map of pending task counts per priority level, like `%{high: 0, normal: 2, low: 1}`. This count should only include tasks that have not yet started processing.

4. `PriorityQueue.drain(server)` — blocks until all currently enqueued tasks have been processed and the queue is empty. This is essential for testing. Returns `:ok`. On an already-empty, idle queue it returns `:ok` immediately.

5. `PriorityQueue.processed(server)` — returns a list of `{task, result}` tuples in the order tasks were processed, and `[]` before anything has been processed.

## Acceptance criteria

- The module is named `PriorityQueue` and is a GenServer.
- The highest priority task available is always processed next, with `:high` > `:normal` > `:low`, and ties within a level broken in FIFO order.
- Tasks are processed one at a time, asynchronously, each in a spawned, monitored process — never inline in the GenServer loop — so `enqueue`, `status`, and `drain` stay responsive during a long-running or blocking task.
- Processing is driven by `:process_next` messages the GenServer sends to itself: on enqueue-while-idle, and after each task finishes when tasks remain.
- `enqueue/3` returns `:ok`; `status/1` reflects only not-yet-started tasks; `drain/1` returns `:ok` (immediately on an empty, idle queue); `processed/1` returns `{task, result}` tuples in processing order, or `[]` before anything has been processed.
- Uses only the OTP standard library, delivered as one complete single-file module.
