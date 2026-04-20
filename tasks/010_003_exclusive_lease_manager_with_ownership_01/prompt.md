Write me an Elixir GenServer module called `LeaseManager` that manages exclusive resource leases with automatic expiration.

I need these functions in the public API:

- `LeaseManager.start_link(opts)` to start the process. It should accept a `:clock` option which is a zero-arity function returning the current time in milliseconds. If not provided, default to `fn -> System.monotonic_time(:millisecond) end`. It should also accept a `:name` option for process registration and a `:lease_duration_ms` option for the default lease duration (default 30000, i.e. 30 seconds).

- `LeaseManager.acquire(server, resource, owner)` which attempts to acquire an exclusive lease on the given resource for the given owner. Return `{:ok, lease_id}` if the resource is available (or its previous lease has expired), or `{:error, :already_held, current_owner}` if another owner holds a valid lease. If the same owner already holds the lease, return `{:error, :already_held, owner}` — acquiring is not idempotent (use `renew` instead). The lease expires at `now + lease_duration_ms`.

- `LeaseManager.release(server, resource, owner)` which releases a lease on the resource. Return `:ok` if the lease existed and was held by the given owner, or `{:error, :not_held}` if no lease exists for the resource, the lease has expired, or the lease is held by a different owner. Only the owner of a lease may release it.

- `LeaseManager.renew(server, resource, owner)` which extends the lease for another full duration from the current time. Return `{:ok, new_expires_at}` if the lease exists and is held by the given owner, or `{:error, :not_held}` if the lease doesn't exist, has expired, or is held by a different owner.

- `LeaseManager.holder(server, resource)` which returns `{:ok, owner, expires_at}` if the resource has a valid (non-expired) lease, or `{:error, :available}` if the resource is available.

- `LeaseManager.force_release(server, resource)` which unconditionally removes any lease on the resource regardless of owner. Return `:ok` always. This is an administrative operation.

Each resource can have at most one active lease at a time — this is a mutual exclusion primitive. Expired leases should be lazily cleaned up on access (treat an expired lease as if the resource is available), and a periodic sweep using `Process.send_after` every 60 seconds (configurable via `:cleanup_interval_ms` option) must remove expired leases to prevent memory leaks.

Lease IDs should be generated using `:crypto.strong_rand_bytes(16) |> Base.url_encode64(padding: false)`.

Give me the complete module in a single file. Use only OTP standard library, no external dependencies.