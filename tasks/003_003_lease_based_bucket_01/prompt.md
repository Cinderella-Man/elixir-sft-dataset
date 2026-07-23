# LeaseBucket — Lease-Based Leaky Bucket Specification

## Overview

This document specifies an Elixir GenServer module named `LeaseBucket` that implements a token-based leaky bucket in which tokens are **reserved via leases** rather than consumed immediately.

The motivation is as follows: in many real-world systems (API quota accounting, connection pools, compute resource allocation), it is not known at request-start whether the operation will succeed, fail, or be cancelled. A consume-on-acquire bucket over-counts cancelled operations. A lease-based bucket allows tokens to be *reserved* at operation start and then either **completed** (tokens permanently consumed) or **cancelled** (tokens refunded to the bucket). Leases that exceed a timeout are pessimistically treated as completed, so that a crashed caller cannot leak reservations indefinitely.

The bucket's free balance must be tracked as a float (for fractional refill math); the `remaining` value returned on acquire is the floor of the float.

The complete module is to be provided in a single file. Only the OTP standard library may be used, with no external dependencies.

## API

The public API must expose the following functions:

- `LeaseBucket.start_link(opts)` starts the process. It should accept a `:clock` option, which is a zero-arity function returning the current time in milliseconds. If not provided, it defaults to `fn -> System.monotonic_time(:millisecond) end`. It should also accept a `:name` option for process registration.

- `LeaseBucket.acquire_lease(server, bucket_name, capacity, refill_rate, tokens, lease_timeout_ms)` attempts to reserve `tokens` from the named bucket for up to `lease_timeout_ms` milliseconds. A bucket that has not been seen before starts with its free balance at full `capacity`. Refills are computed lazily on every call using `new_tokens = min(capacity, old_tokens + elapsed_ms * refill_rate / 1000)`. On success, the tokens are deducted from the bucket's free balance, the lease is recorded, and `{:ok, lease_id, remaining}` is returned, where `lease_id` is an opaque identifier and `remaining` is the floor of the free balance after the reservation. On failure, `{:error, :empty, retry_after_ms}` is returned, where `retry_after_ms` is a positive integer estimating the milliseconds until enough tokens refill. The public function head must be guarded so that out-of-contract arguments raise `FunctionClauseError` rather than being handled at runtime: `capacity`, `tokens`, and `lease_timeout_ms` must be positive integers, `refill_rate` a positive number, and `tokens` must not exceed `capacity`.

- `LeaseBucket.release(server, bucket_name, lease_id, outcome)`, where outcome is `:completed` or `:cancelled`.
  - `:completed` — the operation succeeded; tokens stay consumed. The lease is simply removed from tracking.
  - `:cancelled` — the operation failed or was aborted; the tokens are refunded to the bucket's free balance (capped at capacity). The lease is removed.
  - If `lease_id` does not exist (already released or expired), `{:error, :unknown_lease}` is returned without mutating state. Otherwise `:ok` is returned.

- `LeaseBucket.active_leases(server, bucket_name)` returns `{:ok, count}` with the number of currently outstanding (not yet released or expired) leases for the bucket, or `{:ok, 0}` if the bucket is unknown.

## Edge cases

### Lease expiry

Lease expiry is the trickiest part. Every time any operation touches a bucket (`acquire_lease`, `release`, or the periodic cleanup sweep), the bucket must first expire any of its leases whose `expires_at <= now`. Expired leases are **treated as `:completed`** — tokens are NOT refunded. This is the pessimistic choice: a caller who crashes or forgets to release should not have their quota automatically returned, because that would create an exploit where clients can reserve tokens indefinitely by never releasing them. The lease tracking entry is simply removed. (But by the time execution is in acquire/release/cleanup, the refill clock has been advanced, so those consumed tokens will refill naturally over time like any other completed work.)

### Lease identifiers

Lease IDs should be opaque and globally unique across the server. A monotonic counter formatted as a reference or a binary is fine. Lease data is stored per bucket.

Concretely, the `lease_id` returned by `acquire_lease` must be an Erlang reference created with `make_ref/0` — it must satisfy `is_reference/1`. A counter formatted as a binary or integer must not be used.

### Periodic cleanup

Periodic cleanup is performed via `Process.send_after` every 60 seconds (configurable via `:cleanup_interval_ms`, default 60_000). The cleanup sweep should (a) expire any lease whose `expires_at <= now`, and (b) drop any bucket whose free balance has refilled back to `capacity` AND whose active lease count is zero — such a bucket is indistinguishable from a fresh one.

The `:cleanup_interval_ms` option may also be `:infinity`, in which case the periodic timer is never scheduled — nothing runs automatically.

Sending the server process a bare `:cleanup` message performs one cleanup pass immediately — the same work the periodic timer performs.
