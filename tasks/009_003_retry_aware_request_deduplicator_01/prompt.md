Write me an Elixir GenServer module called `RetryDedup` that deduplicates concurrent identical requests (like a standard coalescer) but automatically retries failed executions with exponential backoff before returning to callers.

I need these functions in the public API:

- `RetryDedup.start_link(opts)` to start the process. It should accept a `:name` option for process registration.

- `RetryDedup.execute(server, key, func, opts \\ [])` where `func` is a zero-arity function. Like a standard deduplicator: if no execution is currently in flight for the given `key`, the function is executed asynchronously and the caller blocks. If another caller calls `execute` with the same key while execution (or retries) are still in progress, it joins the wait list without triggering another execution.

  Options:
    - `:max_retries` — maximum number of retry attempts after the initial failure (default 3)
    - `:base_delay_ms` — initial retry delay in milliseconds (default 100)
    - `:max_delay_ms` — cap on the retry delay (default 5000)

  Retry behaviour: if `func` raises or returns `{:error, reason}`, the GenServer schedules a retry after an exponentially increasing delay: `min(base_delay_ms * 2^attempt, max_delay_ms)`. On retry, `func` is called again in a new spawned Task. If `func` eventually succeeds within the retry budget, all waiting callers receive the success result. If all retries are exhausted, all waiting callers receive the last error.

  Callers that arrive during retries (between attempts) also join the wait list and get the eventual result — they do NOT restart the retry sequence.

  Return value normalisation: if `func` returns `{:ok, value}`, callers get `{:ok, value}`. If `func` returns `{:error, reason}`, callers get `{:error, reason}`. If `func` returns any other term `v`, callers get `{:ok, v}`. If `func` raises, it's treated as `{:error, {:exception, exception}}` for retry purposes.

- `RetryDedup.status(server, key)` which returns `:idle` if no execution is in progress for the key, or `{:retrying, attempt, max_retries}` if retries are in progress (attempt is 1-based, counting from the first retry).

After either final success or final failure, the key is cleared so subsequent calls trigger a fresh execution.

The GenServer must not execute `func` inside `handle_call` — always spawn a Task so the GenServer remains responsive.

Give me the complete module in a single file. Use only OTP standard library, no external dependencies.