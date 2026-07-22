# Connection Pool Manager

Write me an Elixir module called `Pool` (a `GenServer`) that manages a pool of reusable connections. A "connection" is just an opaque term the pool hands out and takes back — it can be a PID, a reference, or any value produced by a factory function you call.

## Public API

- `Pool.start_link(opts)` — start and register the pool process. Support these options:
  - `:name` — an atom to register the process under. All the other API functions are called with this name.
  - `:max_size` — the maximum number of connections the pool may ever have alive at once. Defaults to `10`.
  - `:min_size` — the number of connections to create **eagerly** when the pool starts. Defaults to `0`. Must be `<= max_size`.
  - `:create` — a zero-arity function returning a **new** connection. Defaults to `fn -> make_ref() end`. Every call must return a distinct connection.

- `Pool.checkout(name, timeout)` — borrow a connection.
  - If a connection is available, return `{:ok, conn}` immediately.
  - If none is available but the pool has fewer than `max_size` connections alive, lazily create one (via the `:create` function), hand it out, and return `{:ok, conn}`.
  - If none is available and the pool is already at `max_size`, **block** the caller for up to `timeout` milliseconds waiting for one to be returned. If a connection becomes available in time, return `{:ok, conn}`. Otherwise return `{:error, :timeout}`.
  - A `timeout` of `0` means: return `{:error, :timeout}` right away if nothing is currently available.

- `Pool.checkin(name, conn)` — return a previously checked-out connection to the pool. Returns `:ok`. If another caller is currently blocked waiting in `checkout`, the returned connection should be handed directly to the longest-waiting one.

- `Pool.stats(name)` — return a map `%{available: a, in_use: u, total: t, max: max, min: min}` where `total == a + u`, describing the current state of the pool.

## Required behaviors

- **Lazy growth up to max.** Connections are only created on demand (beyond the `min_size` created at startup), and the pool never creates more than `max_size` connections total. Returned connections are reused rather than recreated.

- **Distinct connections.** No connection is ever handed to two callers at the same time. Two simultaneous checkouts must return two different connections.

- **Ownership monitoring / crash reclamation.** When a process checks out a connection, the pool must monitor it. If that process dies (for any reason) while still holding the connection, the pool must reclaim the connection automatically and make it available again (handing it to a waiting caller if there is one) — without leaking it.

- **Clean timeout.** `checkout` must return `{:error, :timeout}` as a normal value when it cannot get a connection in time. It must **not** crash the caller or the pool. (In particular, don't rely on `GenServer.call`'s own timeout to signal this — implement the waiting/timeout logic inside the server, e.g. with a waiter queue and `Process.send_after` / `GenServer.reply`.)

Use only the OTP standard library — no external dependencies. Give me the complete module in a single file.