Write me an Elixir GenServer module called `QuotaTracker` that tracks per-key usage against configurable rolling-window quotas.

I need these functions in the public API:

- `QuotaTracker.start_link(opts)` to start the process. It should accept a `:clock` option which is a zero-arity function returning the current time in milliseconds. If not provided, default to `fn -> System.monotonic_time(:millisecond) end`. It should also accept a `:name` option for process registration.

- `QuotaTracker.record(server, key, amount, quota, window_ms)` which records `amount` units of usage for the given key against a quota of `quota` within a rolling window of `window_ms` milliseconds. Return `{:ok, remaining}` where remaining is `quota - total_usage_in_window` after recording, or `{:error, :quota_exceeded, overage}` if the recording would push usage above the quota. When the quota would be exceeded, the usage MUST NOT be recorded (all-or-nothing). Usage entries older than `window_ms` from the current time should be evicted on every call.

- `QuotaTracker.remaining(server, key, quota, window_ms)` which returns `{:ok, remaining}` where remaining is `quota - total_usage_in_window` for the given key. If the key has no recorded usage, remaining equals the full quota. This is a read-only operation that does not record anything but still evicts expired entries.

- `QuotaTracker.usage(server, key, window_ms)` which returns `{:ok, total_used}` — the total usage for the key within the rolling window. Returns `{:ok, 0}` if the key has no recorded usage.

- `QuotaTracker.reset(server, key)` which clears all usage history for the given key. Return `:ok` regardless of whether the key existed.

- `QuotaTracker.keys(server)` which returns a list of all keys that have any recorded usage entries (including potentially expired ones — the list is not filtered by window).

Each key tracks usage independently. The rolling window means that usage entries naturally age out — a usage entry recorded at time T is no longer counted after time `T + window_ms`. Multiple `record` calls accumulate: if you record 3 then record 5 with a quota of 10, the remaining is 2.

Expired entries should be lazily cleaned up on access, but you also need a periodic sweep so the GenServer doesn't leak memory. Run a periodic cleanup using `Process.send_after` every 60 seconds (configurable via `:cleanup_interval_ms` option) that removes any keys whose usage lists are completely empty after evicting expired entries. Use a configurable `:max_window_ms` option (default 3600000, i.e. 1 hour) for the sweep — entries older than `max_window_ms` from the current time are always evicted regardless of the per-call `window_ms`.

Give me the complete module in a single file. Use only OTP standard library, no external dependencies.