# Design Brief: `LeaseManager`

## Problem & Constraints

Build an Elixir GenServer module called `LeaseManager` that manages exclusive resource leases with automatic expiration. Each resource can have at most one active lease at a time — this is a mutual exclusion primitive.

Constraints and shared semantics:

- Deliver the complete module in a single file. Use only OTP standard library, no external dependencies.
- A lease is considered expired once the current time reaches or passes its expiry — that is, when `now >= expires_at` (so at exactly `expires_at` the lease is already expired and the resource is available).
- Expired leases should be lazily cleaned up on access (treat an expired lease as if the resource is available).
- A periodic sweep using `Process.send_after` every 60 seconds (configurable via `:cleanup_interval_ms` option) must remove expired leases to prevent memory leaks.
- The `:cleanup_interval_ms` option may also be `:infinity`, in which case the periodic timer is never scheduled — nothing runs automatically.
- Sending the server process a bare `:cleanup` message performs one cleanup pass immediately — the same work the periodic timer performs.
- Lease IDs should be generated using `:crypto.strong_rand_bytes(16) |> Base.url_encode64(padding: false)`.

## Required Interface

1. `LeaseManager.start_link(opts)` — starts the process. It should accept a `:clock` option which is a zero-arity function returning the current time in milliseconds; if not provided, default to `fn -> System.monotonic_time(:millisecond) end`. It should also accept a `:name` option for process registration and a `:lease_duration_ms` option for the default lease duration (default 30000, i.e. 30 seconds).

2. `LeaseManager.acquire(server, resource, owner)` — attempts to acquire an exclusive lease on the given resource for the given owner. Return `{:ok, lease_id}` if the resource is available (or its previous lease has expired), or `{:error, :already_held, current_owner}` if another owner holds a valid lease. If the same owner already holds the lease, return `{:error, :already_held, owner}` — acquiring is not idempotent (use `renew` instead). The lease expires at `now + lease_duration_ms`.

3. `LeaseManager.release(server, resource, owner)` — releases a lease on the resource. Return `:ok` if the lease existed and was held by the given owner, or `{:error, :not_held}` if no lease exists for the resource, the lease has expired, or the lease is held by a different owner. Only the owner of a lease may release it.

4. `LeaseManager.renew(server, resource, owner)` — extends the lease for another full duration from the current time. Return `{:ok, new_expires_at}` if the lease exists and is held by the given owner, or `{:error, :not_held}` if the lease doesn't exist, has expired, or is held by a different owner. `new_expires_at` is `now + lease_duration_ms`.

5. `LeaseManager.holder(server, resource)` — returns `{:ok, owner, expires_at}` if the resource has a valid (non-expired) lease, or `{:error, :available}` if the resource is available.

6. `LeaseManager.force_release(server, resource)` — unconditionally removes any lease on the resource regardless of owner. Return `:ok` always. This is an administrative operation.

## Acceptance Criteria

- All six functions above are exposed as the public API with the exact return contracts described.
- Mutual exclusion holds: each resource has at most one active lease at a time.
- Expiry uses the boundary rule `now >= expires_at`; at exactly `expires_at` the lease is already expired and the resource is available.
- Expired leases are cleaned up lazily on access and by the periodic sweep (`Process.send_after`, every 60 seconds, configurable via `:cleanup_interval_ms`); `:infinity` disables the periodic timer entirely; a bare `:cleanup` message performs one immediate cleanup pass.
- Lease IDs are generated via `:crypto.strong_rand_bytes(16) |> Base.url_encode64(padding: false)`.
- The module is delivered complete in a single file, using only the OTP standard library with no external dependencies.
