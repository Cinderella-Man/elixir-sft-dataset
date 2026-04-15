Write me an Elixir GenServer module called `RetryWorker` that executes a function with exponential backoff and jitter on failure.

I need these functions in the public API:

- `RetryWorker.start_link(opts)` to start the process. It should accept a `:clock` option which is a zero-arity function returning the current time in milliseconds. If not provided, default to `fn -> System.monotonic_time(:millisecond) end`. It should also accept a `:random` option which is a one-arity function that takes a max integer and returns a random integer in `0..max-1`. If not provided, default to `fn max -> :rand.uniform(max) - 1 end`. It should also accept a `:name` option for process registration.

- `RetryWorker.execute(server, func, opts)` which attempts to run the zero-arity function `func`. If `func` returns `{:ok, result}`, return `{:ok, result}` immediately. If `func` returns `{:error, reason}`, schedule a retry with exponential backoff. The opts keyword list must support: `:max_retries` (integer, default 3), `:base_delay_ms` (integer, default 100), and `:max_delay_ms` (integer, default 10_000). The call should block the caller until the function eventually succeeds or all retries are exhausted. When all retries are exhausted return `{:error, :max_retries_exceeded, reason}` where reason is the last error reason.

The backoff delay for attempt N (0-indexed, so first retry is attempt 1) should be calculated as `min(base_delay_ms * 2^N, max_delay_ms)`. Then add random jitter in the range `0..delay-1` on top, so the actual wait is `delay + jitter` where jitter is obtained by calling the injected `:random` function with `delay` as the argument. Retries must be scheduled using `Process.send_after` so the GenServer doesn't block other callers while waiting.

The GenServer should support multiple concurrent `execute` calls — each tracked independently so that one caller's retry schedule doesn't block another caller's work. Use `GenServer.reply/2` to respond asynchronously once a given execution completes or exhausts retries.

The function passed to execute will be called inside the GenServer process. Each retry should call the function again fresh.

Give me the complete module in a single file. Use only OTP standard library, no external dependencies.