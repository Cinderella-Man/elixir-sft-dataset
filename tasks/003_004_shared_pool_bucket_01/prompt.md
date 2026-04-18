Write me an Elixir GenServer module called `SharedPoolBucket` that implements **two-level** token-based rate limiting — each named bucket has its own capacity and refill rate, but all acquires also draw against a shared global pool that constrains the whole server.

The motivation: in multi-tenant systems (SaaS APIs, shared compute clusters), each tenant deserves their own fair allocation (so one tenant can't monopolize), but the infrastructure also has a hard system-wide throughput ceiling (database connections, bandwidth, etc.). A request succeeds only when *both* the tenant's per-key bucket AND the global pool have enough tokens. This is different from a hierarchical limiter (which has multiple tiers per individual key) — here the second level spans across all keys.

I need these functions in the public API:

- `SharedPoolBucket.start_link(opts)` to start the process. The global pool is configured at start time:
  - `:global_capacity` — pool maximum (required, positive integer)
  - `:global_refill_rate` — pool refill rate in tokens/sec (required, positive number)
  - `:clock` — zero-arity function returning current time in ms (default `fn -> System.monotonic_time(:millisecond) end`)
  - `:name` — optional process registration
  - `:cleanup_interval_ms` — periodic sweep interval (default 60_000)

- `SharedPoolBucket.acquire(server, bucket_name, key_capacity, key_refill_rate, tokens \\ 1)` — attempts to drain `tokens` from the named bucket AND from the global pool atomically. Both must have sufficient tokens or the request is rejected and **nothing is drained from either level**. Per-key buckets start full at `key_capacity` when first seen; the global pool starts full at `global_capacity` when the server starts.

  Both levels use the standard lazy-refill formula: `new_tokens = min(capacity, old_tokens + elapsed_ms * refill_rate / 1000)`. Apply the refill to both levels before evaluating the drain.

  Return values:
  - `{:ok, key_remaining, global_remaining}` on success, both as integer floors of the post-drain float balances.
  - `{:error, :key_empty, retry_after_ms}` if the per-key bucket doesn't have enough tokens (retry_after reflects how long until the per-key bucket has enough).
  - `{:error, :global_empty, retry_after_ms}` if the per-key bucket would have admitted but the global pool is insufficient (retry_after reflects the global shortage).
  - If both levels are short, return the **per-key** error first (a caller whose own tier is depleted shouldn't be given the false impression that the global pool is their blocker). This ordering matters — it's explicit in the semantics.

- `SharedPoolBucket.global_level(server)` — returns `{:ok, integer_remaining}` with the floor of the current global pool balance after applying the lazy refill.

- `SharedPoolBucket.key_level(server, bucket_name, key_capacity, key_refill_rate)` — returns `{:ok, integer_remaining}` for the specified per-key bucket (refilled lazily) or `{:ok, key_capacity}` if the bucket has never been seen. The capacity/refill arguments are needed because they're not stored at bucket-creation time — the bucket is defined per-acquire.

Per-bucket state (per key) must track the current token count (float), the last access timestamp, the last-known capacity, and the last-known refill rate. The global pool tracks its own token count (float) and last-refill timestamp in the top-level GenServer state (NOT in the buckets map).

Periodic cleanup via `Process.send_after` every `:cleanup_interval_ms` milliseconds. The sweep drops any per-key bucket whose projected free balance has refilled back to capacity (indistinguishable from a fresh bucket). The global pool is never dropped. Use the injectable clock, not wall time.

Give me the complete module in a single file. Use only OTP standard library, no external dependencies.