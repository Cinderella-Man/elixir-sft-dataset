# Usage-Recycling Connection Pool

Write me an Elixir module called `RecyclingPool` (a `GenServer`) that manages a pool of reusable connections and **retires each connection after it has been used a fixed number of times**, replacing it with a fresh one. A "connection" is an opaque term produced by a factory function — a PID, a reference, or any value.

Long-lived connections accumulate state and eventually should be recycled. This pool caps how many times any single connection may be checked out; once a connection reaches its limit, the pool destroys it (rather than returning it to the available set) and lazily creates a replacement on the next demand.

## Public API

- `RecyclingPool.start_link(opts)` — start and register the pool. Options:
  - `:name` — an atom to register the process under.
  - `:max_size` — the maximum number of connections alive at once. Defaults to `10`.
  - `:min_size` — connections created **eagerly** at startup. Defaults to `0`. Must be `<= max_size`.
  - `:max_uses` — a positive integer, the number of completed uses after which a connection is retired, or `:infinity` for never. Defaults to `:infinity`. One checkout-then-return (or a crash while holding) counts as one use.
  - `:create` — a zero-arity function returning a **new, distinct** connection. Defaults to `fn -> make_ref() end`.
  - `:destroy` — a one-arity function `fn conn -> :ok end` called when a connection is retired. Defaults to a no-op.

- `RecyclingPool.checkout(name, timeout)` — borrow a connection.
  - If a connection is available, hand it out: `{:ok, conn}`.
  - Otherwise, if the pool has fewer than `max_size` connections alive, lazily create one (use count `0`) and hand it out.
  - If the pool is at `max_size` with nothing available, **block** the caller up to `timeout` ms; on success `{:ok, conn}`, otherwise `{:error, :timeout}`. A `timeout` of `0` returns `{:error, :timeout}` immediately.

- `RecyclingPool.checkin(name, conn)` — return a connection. Returns `:ok`. This completes a use: increment the connection's use count.
  - If the connection has reached `:max_uses`, **retire** it (destroy it via `:destroy`, let the total shrink). If a caller is blocked waiting, create a **fresh** connection (use count `0`) for the longest-waiting one instead of handing back the retired one.
  - Otherwise, if a caller is blocked waiting, hand the connection directly to the longest-waiting one; if not, place it back as available.

- `RecyclingPool.stats(name)` — return `%{available: a, in_use: u, total: t, max: max, min: min, max_uses: max_uses}` where `total == a + u`.

## Required behaviors

- **Bounded reuse.** No connection is handed out more than `:max_uses` times; once exhausted it is destroyed and replaced lazily. With `:infinity` no connection is ever retired.
- **Lazy growth up to max**, distinct connections, and reuse of not-yet-exhausted returned connections.
- **Ownership monitoring / crash reclamation.** Monitor the checking-out process; if it dies while holding a connection, reclaim it — this **counts as a use** and may retire the connection (creating a fresh replacement for any waiter).
- **Clean, server-side timeout.** A blocked `checkout` returns `{:error, :timeout}` as a normal value — implement waiting/timeout in the server with a waiter queue and `Process.send_after` / `GenServer.reply`, not via `GenServer.call`'s own timeout.

Use only the OTP standard library — no external dependencies. Give me the complete module in a single file.