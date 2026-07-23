# RetryDedup: Retry-Aware Request Deduplicator Specification

## Overview

This document specifies an Elixir GenServer module named `RetryDedup` that deduplicates concurrent identical requests (like a standard coalescer) but automatically retries failed executions with exponential backoff before returning to callers.

The module must be delivered as a complete module in a single file. It must use only the OTP standard library, with no external dependencies.

The GenServer must not execute `func` inside `handle_call` — it must always spawn a Task so the GenServer remains responsive.

## API

The public API must provide the following functions.

### `RetryDedup.start_link(opts)`

This function starts the process. It should accept a `:name` option for process registration.

### `RetryDedup.execute(server, key, func, opts \\ [])`

Here `func` is a zero-arity function. Like a standard deduplicator: if no execution is currently in flight for the given `key`, the function is executed asynchronously and the caller blocks. If another caller calls `execute` with the same key while execution (or retries) are still in progress, it joins the wait list without triggering another execution.

Options:
  - `:max_retries` — maximum number of retry attempts after the initial failure (default 3)
  - `:base_delay_ms` — initial retry delay in milliseconds (default 100)
  - `:max_delay_ms` — cap on the retry delay (default 5000)

Retry behaviour: if `func` raises or returns `{:error, reason}`, the GenServer schedules a retry after an exponentially increasing delay: `min(base_delay_ms * 2^attempt, max_delay_ms)`. On retry, `func` is called again in a new spawned Task. If `func` eventually succeeds within the retry budget, all waiting callers receive the success result. If all retries are exhausted, all waiting callers receive the last error.

The caller blocks until the final result is available — no matter how long the whole retry sequence takes — so `execute` must not impose its own call timeout (the retry sequence can easily exceed the default 5-second `GenServer.call` timeout).

The GenServer itself must NEVER block during retry delays: retries are scheduled asynchronously (the server stays responsive), so an `execute` for a DIFFERENT key completes immediately even while another key's retry sequence is mid-backoff.

Callers that arrive during retries (between attempts) also join the wait list and get the eventual result — they do NOT restart the retry sequence.

Return value normalisation: if `func` returns `{:ok, value}`, callers get `{:ok, value}`. If `func` returns `{:error, reason}`, callers get `{:error, reason}`. If `func` returns any other term `v`, callers get `{:ok, v}`. If `func` raises, it's treated as `{:error, {:exception, exception}}` for retry purposes — so if all retries are exhausted after a raise, callers get `{:error, {:exception, exception}}` where `exception` is the raised exception struct.

### `RetryDedup.status(server, key)`

This function returns `:idle` if no execution is in progress for the key, or `{:retrying, attempt, max_retries}` if retries are in progress (attempt is 1-based, counting from the first retry).

## Edge cases

After either final success or final failure, the key is cleared so subsequent calls trigger a fresh execution.

Regarding the additional interface contract for `status/2`: it also returns `:idle` during the initial attempt — while `func` is running for the first time and no retry has been scheduled yet, the key's status is `:idle`, indistinguishable from an unknown key. `{:retrying, attempt, max_retries}` appears only once at least one retry has been scheduled.
