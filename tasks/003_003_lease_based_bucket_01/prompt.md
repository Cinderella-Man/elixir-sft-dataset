Write me an Elixir GenServer module called `LeaseBucket` that implements a token-based leaky bucket where tokens are **reserved via leases** rather than consumed immediately.

The motivation: in many real-world systems (API quota accounting, connection pools, compute resource allocation), you don't know at request-start whether the operation will succeed, fail, or be cancelled. A consume-on-acquire bucket over-counts cancelled operations. A lease-based bucket lets you *reserve* tokens at operation start and then either **complete** the lease (tokens permanently consumed) or **cancel** the lease (tokens refunded to the bucket). Leases that exceed a timeout are pessimistically treated as completed, so a crashed caller can't leak reservations indefinitely.

I need these functions in the public API:

- `LeaseBucket.start_link(opts)` to start the process. It should accept a `:clock` option which is a zero-arity function returning the current time in milliseconds. If not provided, default to `fn -> System.monotonic_time(:millisecond) end`. It should also accept a `:name` option for process registration.

- `LeaseBucket.acquire_lease(server, bucket_name, capacity, refill_rate, tokens, lease_timeout_ms)` — attempts to reserve `tokens` from the named bucket for up to `lease_timeout_ms` milliseconds. Refills are computed lazily on every call using `new_tokens = min(capacity, old_tokens + elapsed_ms * refill_rate / 1000)`. On success, deduct the tokens from the bucket's free balance, record the lease, and return `{:ok, lease_id, remaining}` where `lease_id` is an opaque identifier and `remaining` is the floor of the free balance after the reservation. On failure, return `{:error, :empty, retry_after_ms}`.

- `LeaseBucket.release(server, bucket_name, lease_id, outcome)` where outcome is `:completed` or `:cancelled`.
  - `:completed` — the operation succeeded; tokens stay consumed. Just remove the lease from tracking.
  - `:cancelled` — the operation failed or was aborted; refund the tokens to the bucket's free balance (capped at capacity). Remove the lease.
  - If `lease_id` doesn't exist (already released or expired), return `{:error, :unknown_lease}` without mutating state. Otherwise return `:ok`.

- `LeaseBucket.active_leases(server, bucket_name)` — returns `{:ok, count}` with the number of currently outstanding (not yet released or expired) leases for the bucket, or `{:ok, 0}` if the bucket is unknown.

The bucket's free balance must be tracked as a float (for fractional refill math); the `remaining` value returned on acquire is the floor of the float.

**Lease expiry is the trickiest part.** Every time any operation touches a bucket (`acquire_lease`, `release`, or the periodic cleanup sweep), the bucket must first expire any of its leases whose `expires_at <= now`. Expired leases are **treated as `:completed`** — tokens are NOT refunded. This is the pessimistic choice: a caller who crashes or forgets to release should not have their quota automatically returned, because that would create an exploit where clients can reserve tokens indefinitely by never releasing them. The lease tracking entry is simply removed. (But by the time we're in acquire/release/cleanup, the refill clock has been advanced, so those consumed tokens will refill naturally over time like any other completed work.)

Lease IDs should be opaque and globally unique across the server. A monotonic counter formatted as a reference or a binary is fine. Store lease data per bucket.

Periodic cleanup via `Process.send_after` every 60 seconds (configurable via `:cleanup_interval_ms`, default 60_000). The cleanup sweep should (a) expire any lease whose `expires_at <= now`, and (b) drop any bucket whose free balance has refilled back to `capacity` AND whose active lease count is zero — such a bucket is indistinguishable from a fresh one.

Give me the complete module in a single file. Use only OTP standard library, no external dependencies.