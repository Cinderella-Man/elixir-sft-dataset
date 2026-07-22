Write me an Elixir module called `Metrics` that collects **time-windowed event rates** using ETS for fast, concurrent-safe storage. Instead of a single monotonic total, this collector buckets events by the wall-clock second at which they occur, so you can ask "how many events happened in the last N seconds?".

To keep the collector testable, time must be **injectable**: `start_link` accepts a `:clock` option — a zero-arity function returning the current Unix time in integer seconds — defaulting to `fn -> System.system_time(:second) end`.

I need these functions in the public API:

- `Metrics.start_link(opts \\ [])` to start the backing GenServer. It accepts `:name` (process registration, default `__MODULE__`) and `:clock` (as above).
- `Metrics.increment(name, amount \\ 1)` to record `amount` events (a non-negative integer) for `name` at the current second. This is the hot path and MUST NOT serialize through the GenServer — it must go directly to ETS via `:ets.update_counter`, bumping the per-second bucket for `name`.
- `Metrics.rate(name, window_seconds)` to return the total number of events recorded for `name` within the last `window_seconds` — i.e. all events whose bucket second is strictly greater than `now - window_seconds`, where `now` comes from the injected clock.
- `Metrics.count(name)` to return the all-time total number of events recorded for `name` across every bucket.
- `Metrics.reset(name)` to delete every bucket for `name`.
- `Metrics.prune(retention_seconds)` to delete all buckets (across every name) whose second is `<= now - retention_seconds`, returning the number of buckets deleted. This lets the table be bounded over time.
- `Metrics.all()` to return a map of `%{name => all_time_total}`.

The ETS table must be public and named so `increment` can bypass the owning process. The GenServer exists only to own the table; the clock is stored so both the hot path and queries can read it. Use only OTP/stdlib — no external dependencies. Give me the complete implementation in a single file.