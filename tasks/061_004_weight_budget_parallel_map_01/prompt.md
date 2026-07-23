**Summary:** Implement Elixir module `WeightedMap` — parallel map over a collection where the concurrency limit is a **weight budget**, not a task count. Ship a helper GenServer `WeightMeter` in the same file. Single file, complete implementation.

**Public API — `WeightedMap`**
- `WeightedMap.pmap(collection, func, weight_fun, budget)` — the only public function.
- `weight_fun` maps an element to a **positive integer** weight; `budget` is a positive integer.
- Applies `func` to each element in parallel such that the **sum of the weights of all in-flight tasks never exceeds `budget`**.
- Results are returned in the **same order** as the input collection, regardless of completion order.

**Admission / scheduling**
- Admit elements in **strict input order (head-of-line blocking)**: only the element at the head of the queue is eligible to start.
- The head starts only once the currently running total weight plus its own weight is `<= budget`.
- If the head does not fit, nothing behind it may start — a lighter element further back must **not** jump ahead of a blocked heavier head.
- Oversized-element special case: if a single element's weight is **greater than `budget`**, it would otherwise never run — allow it to run **alone**, only when nothing else is currently running. While it runs, no other element may start.

**Validation**
- `pmap/4` validates weights: if `weight_fun` returns anything other than a positive integer for some element (e.g. `0`), it raises an `ArgumentError`.

**Crash handling**
- If `func` raises, or the spawned task exits abnormally, that element's result is `{:error, reason}`.
- A crash must not affect or cancel other in-flight tasks.
- The crashed element's weight must be released back to the budget.

**Helper GenServer — `WeightMeter`** (same file)
- `WeightMeter.start_link(opts)` — starts the process, accepts `:name`.
- `WeightMeter.add(server, weight)` — adds `weight` to the in-flight total, returns the new total.
- `WeightMeter.sub(server, weight)` — subtracts `weight` from the in-flight total, returns the new total.
- `WeightMeter.peak(server)` — returns the highest in-flight total the meter has ever reached.
- Intended for use in tests to verify the weight budget is actually respected at runtime; the `pmap` implementation itself does not need to use it.

**Constraints**
- OTP and standard library only — no external dependencies.
- Do not use `Task.async_stream`.
- Implement the weight-aware admission and scheduling logic yourself using `spawn_monitor`.
- Deliver everything in a single file.
