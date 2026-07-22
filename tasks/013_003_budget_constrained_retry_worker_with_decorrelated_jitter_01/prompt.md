Write me an Elixir GenServer module called `BudgetRetryWorker` that executes a function with retries governed by a total time budget and decorrelated jitter.

I need these functions in the public API:

- `BudgetRetryWorker.start_link(opts)` to start the process. It should accept a `:clock` option which is a zero-arity function returning the current time in milliseconds. If not provided, default to `fn -> System.monotonic_time(:millisecond) end`. It should also accept a `:random` option which is a two-arity function that takes `(min, max)` and returns a random integer in `min..max`. If not provided, default to `fn min, max -> min + :rand.uniform(max - min + 1) - 1 end`. It should also accept a `:name` option for process registration.

- `BudgetRetryWorker.execute(server, func, opts)` which attempts to run the zero-arity function `func`. If `func` returns `{:ok, result}`, return `{:ok, result}` immediately. If `func` returns `{:error, reason}`, schedule a retry if there is still time remaining in the budget. The opts keyword list must support: `:budget_ms` (integer, default 30_000 — total wall-clock time allowed from the first attempt), `:base_delay_ms` (integer, default 100), and `:max_delay_ms` (integer, default 10_000). The call should block the caller until the function eventually succeeds or the time budget is exhausted. When the budget is exhausted return `{:error, :budget_exhausted, reason, attempts}` where `reason` is the last error reason and `attempts` is the total number of attempts made (including the initial one).

The backoff uses **decorrelated jitter** (AWS-style). Track `prev_delay` per execution, starting at `base_delay_ms`. On each retry, compute `next_delay = random(base_delay_ms, prev_delay * 3)`, then cap it: `capped_delay = min(next_delay, max_delay_ms)`. The actual wait is `capped_delay`. Before scheduling a retry, check whether `elapsed_since_start + capped_delay` would exceed `budget_ms`. If it would, do NOT schedule the retry — instead immediately return the budget-exhausted error. Update `prev_delay = capped_delay` for the next iteration.

Elapsed time is calculated by calling the injected `:clock` function and comparing to the timestamp recorded when the execution first started.

Each execution must run OFF the server's call path (e.g. a spawned worker that replies via `GenServer.reply/2`) so the GenServer never blocks other callers while an execution waits. Waits must not busy-spin: sleep in short bounded `receive ... after` ticks between clock checks, so a fake clock can drive the wait deterministically while a real clock never pegs a scheduler.

The clock is read exactly once when an execution starts and exactly once after each failed attempt; that single post-attempt reading drives BOTH the budget check (`elapsed + capped_delay > budget_ms` → give up) and the wait target (`now + capped_delay`). The budget is never re-checked when the wait completes — the next reading happens after the next failed attempt.

The GenServer should support multiple concurrent `execute` calls — each tracked independently so that one caller's retry schedule doesn't block another caller's work. Use `GenServer.reply/2` to respond asynchronously once a given execution completes or exhausts its budget.

The function passed to execute will be called inside that execution's spawned worker process — never inside the GenServer itself, which must stay free to serve other callers. Each retry should call the function again fresh.

Give me the complete module in a single file. Use only OTP standard library, no external dependencies.