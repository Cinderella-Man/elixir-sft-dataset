# ClassifiedRetryWorker Specification

## Overview

This document specifies an Elixir GenServer module named `ClassifiedRetryWorker`. The module executes a function with exponential backoff and classifies errors as transient (retryable) or permanent (non-retryable), with an optional on_retry callback.

The function passed to execute is called inside the GenServer process. Each retry calls the function again fresh. A function may return transient errors on some attempts and a permanent error on a later attempt — the permanent error must immediately stop retries regardless of remaining retry budget.

The GenServer supports multiple concurrent `execute` calls, each tracked independently so that one caller's retry schedule does not block another caller's work. `GenServer.reply/2` must be used to respond asynchronously once a given execution completes or exhausts retries.

The complete module must be delivered in a single file. Only the OTP standard library may be used — no external dependencies.

## API

The public API must include the following functions.

### `ClassifiedRetryWorker.start_link(opts)`

Starts the process. It accepts:

- A `:clock` option, which is a zero-arity function returning the current time in milliseconds. If not provided, it defaults to `fn -> System.monotonic_time(:millisecond) end`.
- A `:random` option, which is a one-arity function that takes a max integer and returns a random integer in `0..max-1`. If not provided, it defaults to `fn max -> :rand.uniform(max) - 1 end`.
- A `:name` option for process registration.

### `ClassifiedRetryWorker.execute(server, func, opts)`

Attempts to run the zero-arity function `func`. The function must return one of three shapes:

- `{:ok, result}` — success; return `{:ok, result}` to the caller immediately.
- `{:error, :transient, reason}` — a retryable failure; schedule a retry with exponential backoff.
- `{:error, :permanent, reason}` — a non-retryable failure; return `{:error, :permanent, reason}` to the caller immediately with no retries.

The opts keyword list must support:

- `:max_retries` (integer, default 3)
- `:base_delay_ms` (integer, default 100)
- `:max_delay_ms` (integer, default 10_000)
- `:on_retry` — an optional 3-arity callback function `fn attempt, reason, delay -> ... end` that is called inside the GenServer before each retry is scheduled. The `attempt` is the upcoming attempt number (1-indexed, so the first retry is attempt 1), `reason` is the error reason from the failed attempt, and `delay` is the computed total delay (including jitter). If `:on_retry` is not provided, no callback is invoked.

## Backoff and timing

The backoff delay for the Nth retry (1-indexed, so the first retry is N=1) is calculated as `min(base_delay_ms * 2^(N-1), max_delay_ms)`. With the default `base_delay_ms` of 100, the first retry's base delay is 100, the second is 200, the third is 400, and so on.

Random jitter in the range `0..delay-1` is then added on top, so the actual wait is `delay + jitter`, where `jitter` is obtained by calling the injected `:random` function with this capped `delay` as the argument.

The wait itself is MEASURED AGAINST the injected `:clock`: schedule short ticks to yourself with `Process.send_after` (so the GenServer never blocks other callers) and run the retry once the clock reaches `scheduled_at + total_wait`. A fake clock therefore drives retries deterministically, and a retry must NOT fire while the clock still reads below its target.

## Edge cases

- When all retries are exhausted on transient errors, return `{:error, :retries_exhausted, reason}`, where reason is the last transient error reason.
- A permanent error must immediately stop retries regardless of remaining retry budget, even if it follows earlier transient errors from the same execution.
- If `:on_retry` is not provided, no callback is invoked.
