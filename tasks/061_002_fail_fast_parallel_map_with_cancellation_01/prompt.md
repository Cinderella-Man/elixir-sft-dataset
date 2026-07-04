Write me an Elixir module called `FailFastMap` that applies a function to a collection
in parallel with a maximum concurrency limit, but using **fail-fast** semantics instead
of collecting per-element errors.

I need one public function:
- `FailFastMap.pmap(collection, func, max_concurrency)` which applies `func` to each
  element of `collection` in parallel, with at most `max_concurrency` tasks running at
  the same time.

Result semantics (this is the key difference from a normal parallel map):
- If **every** element succeeds, return `{:ok, results}` where `results` is the list of
  return values in the **same order** as the input collection.
- If **any** element's `func` raises or its task exits abnormally, immediately
  short-circuit: return `{:error, {index, reason}}` where `index` is the zero-based
  position of the failing element and `reason` describes the failure. As soon as a
  failure is detected you must **cancel all still-running tasks** (kill their processes)
  and you must **not** start any queued elements that had not yet begun.
- An empty collection returns `{:ok, []}`.

For concurrency enforcement: use a pool/semaphore approach so that at no point are more
than `max_concurrency` tasks alive simultaneously. A new task should only be spawned once
a running one has finished (or when you are still filling the initial window).

You will also need to write a helper GenServer called `ConcurrencyCounter` in the same
file. It must expose:
- `ConcurrencyCounter.start_link(opts)` — starts the process, accepts `:name`
- `ConcurrencyCounter.increment(server)` — increments the active count, returns the new value
- `ConcurrencyCounter.decrement(server)` — decrements the active count, returns the new value
- `ConcurrencyCounter.peak(server)` — returns the highest value the counter has ever reached
- `ConcurrencyCounter.started(server)` — returns how many times `increment/1` has ever been called

`ConcurrencyCounter` is intended for use in tests to verify both the concurrency limit and
that queued work is genuinely cancelled after a failure; your `pmap` implementation itself
does not need to use it.

Give me the complete implementation in a single file. Use only OTP and the standard
library — no external dependencies. Do not use `Task.async_stream`; implement the
scheduling and cancellation logic yourself using `spawn_monitor` / `Process.exit`.