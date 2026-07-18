Write me an Elixir module called `WeightedMap` that applies a function to a collection in
parallel, but where the concurrency limit is a **weight budget** rather than a simple task
count.

I need one public function:
- `WeightedMap.pmap(collection, func, weight_fun, budget)` where `weight_fun` maps an
  element to a **positive integer** weight and `budget` is a positive integer. It applies
  `func` to each element in parallel such that the **sum of the weights of all in-flight
  tasks never exceeds `budget`**. Results are returned in the **same order** as the input
  collection, regardless of completion order.

Admission rules:
- Admit elements in **strict input order (head-of-line blocking)**: only the element at the
  head of the queue is eligible to start, and it starts only once the currently running
  total weight plus its own weight is `<= budget`. If the head does not fit, nothing behind
  it may start — a lighter element further back must **not** jump ahead of a blocked heavier
  head.
- Special case: if a single element's weight is **greater than `budget`**, it would
  otherwise never run — so allow it to run **alone** (only when nothing else is currently
  running). While it runs, no other element may start.

Task crash handling: if `func` raises or the spawned task exits abnormally for a given
element, that element's result should be `{:error, reason}` — this must not affect or cancel
other in-flight tasks, and the element's weight must be released back to the budget.

You will also need to write a helper GenServer called `WeightMeter` in the same file. It must
expose:
- `WeightMeter.start_link(opts)` — starts the process, accepts `:name`
- `WeightMeter.add(server, weight)` — adds `weight` to the in-flight total, returns the new total
- `WeightMeter.sub(server, weight)` — subtracts `weight` from the in-flight total, returns the new total
- `WeightMeter.peak(server)` — returns the highest in-flight total the meter has ever reached

`WeightMeter` is intended for use in tests to verify that the weight budget is actually
respected at runtime; your `pmap` implementation itself does not need to use it.

Give me the complete implementation in a single file. Use only OTP and the standard library —
no external dependencies. Do not use `Task.async_stream`; implement the weight-aware
admission and scheduling logic yourself using `spawn_monitor`.

## Additional interface contract

- `pmap/4` validates weights: if `weight_fun` returns anything other than a positive
  integer for some element (e.g. `0`), it raises an `ArgumentError`.
