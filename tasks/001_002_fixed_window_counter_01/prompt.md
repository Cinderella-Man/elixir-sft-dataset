# FixedWindowLimiter Specification

## Overview

This document specifies an Elixir GenServer module named `FixedWindowLimiter` that enforces per-key rate limits using a fixed-window counter algorithm. The complete module is to be delivered in a single file, using only the OTP standard library with no external dependencies.

The algorithm snaps time into discrete fixed windows: the window a timestamp belongs to is `div(timestamp, window_ms)`. Each `{key, window_index}` pair maintains an independent counter.

Each key is tracked independently — rate limiting `"user:1"` has no effect on `"user:2"`. Windows are absolute, not relative: with a 1000ms window, timestamps 0-999 belong to window 0, 1000-1999 belong to window 1, and so on. Consequently, the counter resets abruptly at window boundaries. This is a known property of fixed-window counters: a client could send max_requests at t=999 and max_requests again at t=1000, effectively doubling the rate at the boundary. That behavior is acceptable for this implementation and is not to be smoothed out.

## API

The public API consists of the following functions:

- `FixedWindowLimiter.start_link(opts)` starts the process. It accepts a `:clock` option, which is a zero-arity function returning the current time in milliseconds; if not provided, it defaults to `fn -> System.monotonic_time(:millisecond) end`. It also accepts a `:name` option for process registration.

- `FixedWindowLimiter.check(server, key, max_requests, window_ms)` checks whether a request for the given key is allowed. If the counter for the current window is below max_requests, the request is allowed and the counter is incremented — it returns `{:ok, remaining}`, where `remaining` is the number of additional requests still permitted in the current window after this one (that is, `max_requests` minus the new counter value; so the first of three allowed calls returns `{:ok, max_requests - 1}` and the last returns `{:ok, 0}`). If the counter has reached max_requests, it returns `{:error, :rate_limited, retry_after_ms}`, where retry_after_ms is the time until the current window ends (when the counter resets) — that is, `window_end_time - current_time`, which is always a positive integer no greater than window_ms.

## Edge cases

- Expired counter entries must be cleaned up so the GenServer does not leak memory over time. A periodic cleanup runs using `Process.send_after` every 60 seconds (configurable via the `:cleanup_interval_ms` option) that removes any counter whose window has fully ended (window_end_time < current time).

- The `:cleanup_interval_ms` option may also be `:infinity`, in which case the periodic timer is never scheduled — nothing runs automatically.

- Sending the server process a bare `:cleanup` message performs one cleanup pass immediately — the same work the periodic timer performs.
