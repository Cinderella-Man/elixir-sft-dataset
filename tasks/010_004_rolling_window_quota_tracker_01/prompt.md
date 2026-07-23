# Design Brief: `QuotaTracker`

## Problem & Constraints

We need an Elixir GenServer module called `QuotaTracker` that tracks per-key usage against configurable rolling-window quotas. Each key tracks usage independently.

Constraints and background behavior that shape the whole design:

- The rolling window means usage entries naturally age out — a usage entry recorded at time T is no longer counted once the current time reaches `T + window_ms` (i.e. an entry is counted only while its age is strictly less than `window_ms`).
- Multiple `record` calls accumulate: if you record 3 then record 5 with a quota of 10, the remaining is 2.
- Expired entries should be lazily cleaned up on access, but you also need a periodic sweep so the GenServer doesn't leak memory. Run a periodic cleanup using `Process.send_after` every 60 seconds (configurable via `:cleanup_interval_ms` option) that removes any keys whose usage lists are completely empty after evicting expired entries.
- Use a configurable `:max_window_ms` option (default 3600000, i.e. 1 hour) for the sweep — entries older than `max_window_ms` from the current time are always evicted regardless of the per-call `window_ms` (an entry is evicted once its age reaches `max_window_ms`).
- Deliver the complete module in a single file. Use only OTP standard library, no external dependencies.

## Required Interface

1. `QuotaTracker.start_link(opts)` to start the process. It should accept a `:clock` option which is a zero-arity function returning the current time in milliseconds. If not provided, default to `fn -> System.monotonic_time(:millisecond) end`. It should also accept a `:name` option for process registration.

2. `QuotaTracker.record(server, key, amount, quota, window_ms)` which records `amount` units of usage for the given key against a quota of `quota` within a rolling window of `window_ms` milliseconds. Return `{:ok, remaining}` where remaining is `quota - total_usage_in_window` after recording, or `{:error, :quota_exceeded, overage}` if the recording would push usage above the quota, where `overage` is `(total_usage_in_window + amount) - quota` (the number of units by which the attempted recording overshoots the quota). When the quota would be exceeded, the usage MUST NOT be recorded (all-or-nothing). The per-call `window_ms` only determines which entries are counted for that call — it never removes anything from storage; stored entries are evicted only once they age past the tracker-wide `:max_window_ms` (lazily on access, and via the periodic sweep described above), so an entry outside one call's small window is still counted by a later call that uses a larger window.

3. `QuotaTracker.remaining(server, key, quota, window_ms)` which returns `{:ok, remaining}` where remaining is `quota - total_usage_in_window` for the given key. If the key has no recorded usage, remaining equals the full quota. This value is NOT clamped — if usage exceeds the quota, remaining is negative. This is a read-only operation that does not record anything but still performs the lazy cleanup (evicting stored entries older than `:max_window_ms`).

4. `QuotaTracker.usage(server, key, window_ms)` which returns `{:ok, total_used}` — the total usage for the key within the rolling window. Returns `{:ok, 0}` if the key has no recorded usage.

5. `QuotaTracker.reset(server, key)` which clears all usage history for the given key. Return `:ok` regardless of whether the key existed.

6. `QuotaTracker.keys(server)` which returns a list of all keys that have any recorded usage entries (including potentially expired ones — the list is not filtered by the per-call window, though keys are dropped once all their entries age past `:max_window_ms` and are evicted).

7. The `:cleanup_interval_ms` option may also be `:infinity`, in which case the periodic timer is never scheduled — nothing runs automatically.

8. Sending the server process a bare `:cleanup` message performs one cleanup pass immediately — the same work the periodic timer performs.

## Acceptance Criteria

- `record` returns `{:ok, remaining}` with `remaining = quota - total_usage_in_window` after recording, and `{:error, :quota_exceeded, overage}` with `overage = (total_usage_in_window + amount) - quota` when the recording would push usage above the quota; in the exceeded case the usage is not recorded (all-or-nothing).
- The per-call `window_ms` only selects which entries are counted for that call and never removes anything from storage; eviction happens only once entries age past `:max_window_ms`.
- `remaining` returns `{:ok, quota - total_usage_in_window}`, equals the full quota when there is no recorded usage, is unclamped (negative when usage exceeds quota), records nothing, and still performs the lazy cleanup evicting entries older than `:max_window_ms`.
- `usage` returns `{:ok, total_used}` for the rolling window, and `{:ok, 0}` when the key has no recorded usage.
- `reset` clears the key's history and returns `:ok` whether or not the key existed.
- `keys` lists every key with any recorded entries (unfiltered by per-call window), dropping keys only once all their entries age past `:max_window_ms` and are evicted.
- Entries are counted only while their age is strictly less than `window_ms`; accumulation across multiple `record` calls behaves as described.
- The periodic sweep uses `Process.send_after` at the `:cleanup_interval_ms` interval (default 60 seconds), removes keys whose usage lists are empty after evicting expired entries, and uses `:max_window_ms` (default 3600000) so entries reaching that age are always evicted regardless of per-call `window_ms`.
- With `:cleanup_interval_ms` set to `:infinity`, no periodic timer is scheduled and nothing runs automatically.
- A bare `:cleanup` message triggers one immediate cleanup pass identical to the periodic timer's work.
- `start_link/1` honors `:clock` (defaulting to `fn -> System.monotonic_time(:millisecond) end`) and `:name` for registration.
- The deliverable is the complete module in a single file using only the OTP standard library, with no external dependencies.
