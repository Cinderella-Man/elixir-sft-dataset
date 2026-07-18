# Overflow Connection Pool

Write me an Elixir module called `OverflowPool` (a `GenServer`) that manages a pool of reusable connections with **poolboy-style overflow semantics**. A "connection" is an opaque term produced by a factory function — a PID, a reference, or any value.

The pool keeps a fixed base of persistent connections but can create a bounded number of **temporary overflow connections** under load. When an overflow connection is no longer needed, it is destroyed rather than kept, so the pool shrinks back to its base size during quiet periods.

## Public API

- `OverflowPool.start_link(opts)` — start and register the pool. Options:
  - `:name` — an atom to register the process under.
  - `:size` — the number of **persistent** connections, created **eagerly** at startup. Defaults to `5`.
  - `:max_overflow` — the maximum number of extra temporary connections allowed beyond `:size`. Defaults to `0`. The pool never has more than `size + max_overflow` connections alive at once.
  - `:create` — a zero-arity function returning a **new, distinct** connection. Defaults to `fn -> make_ref() end`.
  - `:destroy` — a one-arity function `fn conn -> :ok end` called when an overflow connection is dismissed. Defaults to a no-op.

- `OverflowPool.checkout(name, timeout)` — borrow a connection.
  - If a connection is available, hand it out immediately: `{:ok, conn}`.
  - Otherwise, if the pool has fewer than `size + max_overflow` connections alive, lazily create one and hand it out (this is an overflow connection when the base is already fully in use).
  - If the pool is at `size + max_overflow`, **block** the caller up to `timeout` ms; on success `{:ok, conn}`, otherwise `{:error, :timeout}`. A `timeout` of `0` returns `{:error, :timeout}` immediately.

- `OverflowPool.checkin(name, conn)` — return a connection. Returns `:ok`.
  - If a caller is blocked waiting, hand the connection **directly** to the longest-waiting one (the connection stays alive regardless of overflow — demand still exists).
  - Otherwise, if the pool currently has **more than `size`** connections alive, this connection is an overflow connection: **destroy** it (via `:destroy`) and let the total shrink back toward `size`. If the pool is at or below `size`, keep the connection available for reuse.

- `OverflowPool.stats(name)` — return `%{available: a, in_use: u, total: t, size: size, max_overflow: max_overflow, overflow: o}` where `a` and `u` are the counts of available and in-use connections, `total == a + u`, and `overflow == max(0, total - size)`.

## Required behaviors

- **Eager base, lazy overflow.** Exactly `:size` connections exist at startup; overflow connections are created only on demand and never exceed `max_size = size + max_overflow` total.
- **Overflow connections are ephemeral.** A returned overflow connection with no waiter is destroyed, not pooled — but if a caller is waiting, it is handed over and stays alive.
- **Distinct connections.** No connection is handed to two callers at once.
- **Ownership monitoring / crash reclamation.** Monitor the checking-out process; if it dies while holding a connection, reclaim it (handing to a waiter, or destroying if it is now overflow). If instead it dies while still blocked in the waiter queue, drop it from the queue so it is never served — a later checkin then goes to the next still-live waiter.
- **Clean, server-side timeout.** A blocked `checkout` returns `{:error, :timeout}` as a normal value, and a waiter that has already timed out is retired: a later checkin must not hand it a connection but instead reuse the connection normally. Implement waiting/timeout in the server with a waiter queue and `Process.send_after` / `GenServer.reply`, not via `GenServer.call`'s own timeout.

Use only the OTP standard library — no external dependencies. Give me the complete module in a single file.
