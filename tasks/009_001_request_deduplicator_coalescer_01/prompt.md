Write me an Elixir GenServer module called `Dedup` that deduplicates concurrent identical requests so that only one execution happens per key at a time.

I need these functions in the public API:

- `Dedup.start_link(opts)` to start the process. It should accept a `:name` option for process registration.

- `Dedup.execute(server, key, func)` where `func` is a zero-arity function. If no execution is currently in flight for the given `key`, the function is executed (asynchronously, so the GenServer isn't blocked) and the caller blocks until the result is ready. If another caller calls `execute` with the same key while the first execution is still running, it does **not** call `func` again — instead it blocks and waits for the already-in-flight execution to finish. Once the function completes, **all** waiting callers receive the same result and the key is cleared so future calls with that key will trigger a fresh execution.

- If `func` raises an exception or returns `{:error, reason}`, all waiting callers should receive the error. Specifically: if `func` raises, every caller gets `{:error, {:exception, exception}}` returned. If `func` returns `{:error, reason}`, every caller gets that `{:error, reason}` as-is. If `func` returns `{:ok, value}` or any other non-error term, every caller gets `{:ok, value}` (wrap plain values in `{:ok, value}` if they aren't already an ok-tuple). After either success or failure, the key must be cleared so subsequent calls trigger a new execution.

The GenServer should not execute `func` inside `handle_call` directly — spawn a task or use `Task.async` so the GenServer remains responsive to new callers registering on the same or different keys while a function is running.

Keep track of waiting callers using a list of `GenServer.from()` references so you can reply to all of them when the result arrives.

Give me the complete module in a single file. Use only OTP standard library, no external dependencies.