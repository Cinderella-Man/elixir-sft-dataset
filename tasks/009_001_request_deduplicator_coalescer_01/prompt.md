**Ticket: `Dedup` — GenServer request deduplicator/coalescer**

Implement an Elixir GenServer module named `Dedup` that deduplicates concurrent identical requests so only one execution happens per key at a time. Deliver the complete module in a single file.

**Public API**

- `Dedup.start_link(opts)` — starts the process; must accept a `:name` option for process registration.
- `Dedup.execute(server, key, func)` — `func` is a zero-arity function.
  - If no execution is currently in flight for `key`: run the function asynchronously (so the GenServer is not blocked), and the caller blocks until the result is ready.
  - If another caller calls `execute` with the same key while the first execution is still running: do **not** call `func` again — that caller blocks and waits for the already-in-flight execution to finish.
  - When the function completes: **all** waiting callers receive the same result, and the key is cleared so future calls with that key trigger a fresh execution.

**Result and error semantics** (apply to all waiting callers)

- If `func` raises: every caller gets `{:error, {:exception, exception}}`.
- If `func` returns `{:error, reason}`: every caller gets that `{:error, reason}` as-is.
- If `func` returns `{:ok, value}` or any other non-error term: every caller gets `{:ok, value}` (wrap plain values in `{:ok, value}` if they aren't already an ok-tuple).
- After either success or failure, the key must be cleared so subsequent calls trigger a new execution.

**Concurrency**

- Do not execute `func` inside `handle_call` directly — spawn a task or use `Task.async` so the GenServer stays responsive to new callers registering on the same or different keys while a function is running.
- Track waiting callers using a list of `GenServer.from()` references, so all of them can be replied to when the result arrives.

**Constraints**

- Single file, complete module.
- Use only the OTP standard library; no external dependencies.
