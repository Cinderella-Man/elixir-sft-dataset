# `WorkStealQueue` — Priority-Aware Work-Stealing Task Distributor

## Overview

This document specifies an Elixir module named `WorkStealQueue` that distributes **prioritized** work across N worker processes by means of a work-stealing algorithm. Within each worker, higher-priority work is to be done first. When an idle worker steals, it takes the *least urgent* work off a busy peer — leaving the busy worker to keep grinding on its most urgent items.

The deliverable is the complete implementation in a single file.

## API

One primary public function is required:

- `WorkStealQueue.run(items, worker_count, process_fn)` — `items` is a list of `{priority, payload}` tuples in which `priority` is an integer (higher = more urgent). `worker_count` is the number of workers to spawn. `process_fn` is a one-arity function applied to each **payload**. The call returns a list of `%{item: payload, priority: priority, result: term, worker_id: non_neg_integer}` maps — one per input tuple, in any order. An empty `items` list returns `[]`.

## Internal Operation

The module is expected to work as follows:

1. The input list is partitioned as evenly as possible across `worker_count` workers, **preserving input order**, so that worker `0` receives the first contiguous chunk, worker `1` the next, and so on. Each worker owns a local priority queue kept sorted such that the highest-priority item is always next.
2. All workers are spawned as `Task`s. Each worker repeatedly pops and processes its **highest-priority** local item, applying `process_fn` to the payload.
3. When a worker empties its local queue, it *steals* from the busiest worker (the one with the most items remaining). A steal takes the **lowest-priority half** of the victim's queue (the back of its sorted queue), so that the victim retains its most urgent work. If no other worker has any remaining work, the stealing worker simply exits.
4. Each worker tags every result with its own `worker_id` (`0` to `worker_count - 1`) and echoes back the item's `priority`.

## Coordination Requirements

- A shared coordination mechanism (e.g. an `Agent` or `GenServer`) must track each worker's remaining sorted queue, so that steal attempts can find the busiest worker and slice off its lowest-priority items atomically. Failed steals (victim emptied first) are to be handled gracefully, by retrying or moving on.
- `run/3` must be synchronous: it blocks until every item is processed, then returns the full result list.

## Edge Cases and Constraints

- Only OTP/stdlib may be used — no external dependencies.
- The implementation must work correctly when `worker_count` is greater than `length(items)`.
- Within a single worker, items must be processed in strictly descending priority order.
- `process_fn` may be slow or fast — faster workers should naturally pick up the low-priority slack.
