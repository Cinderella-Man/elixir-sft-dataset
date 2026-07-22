Write me an Elixir module called `RetryMap` that applies a function to a collection in
parallel, enforcing a maximum concurrency limit **and** giving each element a per-attempt
timeout with bounded retries.

I need one public function:
- `RetryMap.pmap(collection, func, opts)` where `opts` is a keyword list accepting:
  - `:max_concurrency` — the maximum number of tasks alive at once (default `5`)
  - `:timeout` — the per-attempt timeout in milliseconds (default `5000`)
  - `:max_attempts` — the maximum number of attempts per element (default `1`)

It applies `func` to each element in parallel with at most `max_concurrency` tasks alive
simultaneously, and returns a list — in the **same order** as the input — of tagged
results, one per element.

Per-element semantics:
- If an attempt returns a value within `:timeout`, that element's result is `{:ok, value}`.
- If an attempt does **not** finish within `:timeout`, kill that attempt and retry, up to a
  total of `:max_attempts` attempts. If all attempts time out, the result is
  `{:error, :timeout}`.
- If `func` raises (or the task exits abnormally), that is a **permanent** failure — do
  **not** retry — and the result is `{:error, {:exception, reason}}` (or a similarly tagged
  error for a non-exception failure). A crash or timeout for one element must not affect any
  other element.

For concurrency enforcement: use a pool/semaphore approach so that at no point are more than
`max_concurrency` tasks alive simultaneously. A freed slot is filled from the queue once an
element reaches a terminal result; a retry of a timed-out element reuses that element's slot.

You will also need to write a helper GenServer called `ConcurrencyCounter` in the same file.
It must expose:
- `ConcurrencyCounter.start_link(opts)` — starts the process, accepts `:name`
- `ConcurrencyCounter.increment(server)` — increments the active count, returns the new value
- `ConcurrencyCounter.decrement(server)` — decrements the active count, returns the new value
- `ConcurrencyCounter.peak(server)` — returns the highest value the counter has ever reached

`ConcurrencyCounter` is intended for use in tests to verify the concurrency limit is actually
respected at runtime; your `pmap` implementation itself does not need to use it.

Give me the complete implementation in a single file. Use only OTP and the standard library —
no external dependencies. Do not use `Task.async_stream`; implement the scheduling, timeout,
and retry logic yourself using `spawn_monitor`, `Process.send_after`, and `Process.exit`.