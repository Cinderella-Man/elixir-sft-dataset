Write me an Elixir module called `ParallelMap` that applies a function to a collection
in parallel while enforcing a maximum concurrency limit.

I need one public function:
- `ParallelMap.pmap(collection, func, max_concurrency)` which applies `func` to each
  element of `collection` in parallel, with at most `max_concurrency` tasks running at
  the same time. It must return results in the same order as the input collection,
  regardless of completion order.

Task crash handling: if `func` raises or the spawned task exits abnormally for a given
element, that element's result should be `{:error, reason}` — this must not affect or
cancel other in-flight tasks.

For concurrency enforcement: use a pool/semaphore approach so that at no point are more
than `max_concurrency` tasks alive simultaneously. A new task should only be spawned once
a running one has finished (or crashed).

You will also need to write a helper GenServer called `ConcurrencyCounter` in the same
file. It must expose:
- `ConcurrencyCounter.start_link(opts)` — starts the process, accepts `:name`
- `ConcurrencyCounter.increment(server)` — increments the active count, returns the new value
- `ConcurrencyCounter.decrement(server)` — decrements the active count, returns the new value
- `ConcurrencyCounter.peak(server)` — returns the highest value the counter has ever reached

`ConcurrencyCounter` is intended for use in tests to verify the concurrency limit is
actually respected at runtime — your `pmap` implementation itself does not need to use it.

Give me the complete implementation in a single file. Use only OTP and the standard
library — no external dependencies. Do not use `Task.async_stream`; implement the
scheduling logic yourself using `Task.async` / `Task.yield`.