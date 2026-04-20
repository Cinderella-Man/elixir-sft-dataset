Write me an Elixir GenServer module called `ClassifiedRetryWorker` that executes a function with exponential backoff and classifies errors as transient (retryable) or permanent (non-retryable), with an optional on_retry callback.

I need these functions in the public API:

- `ClassifiedRetryWorker.start_link(opts)` to start the process. It should accept a `:clock` option which is a zero-arity function returning the current time in milliseconds. If not provided, default to `fn -> System.monotonic_time(:millisecond) end`. It should also accept a `:random` option which is a one-arity function that takes a max integer and returns a random integer in `0..max-1`. If not provided, default to `fn max -> :rand.uniform(max) - 1 end`. It should also accept a `:name` option for process registration.

- `ClassifiedRetryWorker.execute(server, func, opts)` which attempts to run the zero-arity function `func`. The function must return one of three shapes:
  - `{:ok, result}` — success, return `{:ok, result}` to caller immediately.
  - `{:error, :transient, reason}` — a retryable failure, schedule a retry with exponential backoff.
  - `{:error, :permanent, reason}` — a non-retryable failure, return `{:error, :permanent, reason}` to caller immediately with no retries.

  The opts keyword list must support: `:max_retries` (integer, default 3), `:base_delay_ms` (integer, default 100), `:max_delay_ms` (integer, default 10_000), and `:on_retry` — an optional 3-arity callback function `fn attempt, reason, delay -> ... end` that is called inside the GenServer before each retry is scheduled. The `attempt` is the upcoming attempt number (1-indexed, so the first retry is attempt 1), `reason` is the error reason from the failed attempt, and `delay` is the computed total delay (including jitter). If `:on_retry` is not provided, no callback is invoked.

The backoff delay for attempt N (0-indexed, so first retry is attempt 1) should be calculated as `min(base_delay_ms * 2^N, max_delay_ms)`. Then add random jitter in the range `0..delay-1` on top, so the actual wait is `delay + jitter` where jitter is obtained by calling the injected `:random` function with `delay` as the argument. Retries must be scheduled using `Process.send_after` so the GenServer doesn't block other callers while waiting.

When all retries are exhausted on transient errors, return `{:error, :retries_exhausted, reason}` where reason is the last transient error reason.

The GenServer should support multiple concurrent `execute` calls — each tracked independently so that one caller's retry schedule doesn't block another caller's work. Use `GenServer.reply/2` to respond asynchronously once a given execution completes or exhausts retries.

The function passed to execute will be called inside the GenServer process. Each retry should call the function again fresh. Note that a function may return transient errors on some attempts and a permanent error on a later attempt — the permanent error should immediately stop retries regardless of remaining retry budget.

Give me the complete module in a single file. Use only OTP standard library, no external dependencies.