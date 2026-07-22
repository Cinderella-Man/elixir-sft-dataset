# Health-Validated Connection Pool

Write me an Elixir module called `ValidatingPool` (a `GenServer`) that manages a pool of reusable connections **and validates every connection right before it hands it to a caller**. A "connection" is an opaque term produced by a factory function — a PID, a reference, or any value.

Unlike a plain pool, connections in a real system go stale (a socket closes, a DB session dies). This pool must never hand out a connection that fails validation: it checks each candidate first and silently discards the bad ones, replacing them so the caller always receives a healthy connection.

## Public API

- `ValidatingPool.start_link(opts)` — start and register the pool. Options:
  - `:name` — an atom to register the process under.
  - `:max_size` — the maximum number of connections alive at once. Defaults to `10`.
  - `:min_size` — connections created **eagerly** at startup. Defaults to `0`. Must be `<= max_size`.
  - `:create` — a zero-arity function returning a **new, distinct** connection. Defaults to `fn -> make_ref() end`.
  - `:validate` — a one-arity function `fn conn -> boolean end`. Defaults to `fn _ -> true end`. Called just before a connection is handed out.
  - `:destroy` — a one-arity function `fn conn -> :ok end` called when a connection is discarded. Defaults to a no-op.

- `ValidatingPool.checkout(name, timeout)` — borrow a **valid** connection.
  - Take connections from the available set one at a time; for each, call `:validate`. If it returns `false`, call `:destroy` on it, drop it from the pool (the total shrinks), and try the next one.
  - If a valid available connection is found, hand it out: `{:ok, conn}`.
  - If none are available (or all were discarded) and the pool has fewer than `max_size` connections alive, lazily create a fresh one (assumed valid) and hand it out.
  - If the pool is at `max_size` with nothing available, **block** the caller up to `timeout` ms for a connection to be returned; on success `{:ok, conn}`, otherwise `{:error, :timeout}`. A `timeout` of `0` returns `{:error, :timeout}` immediately.

- `ValidatingPool.checkin(name, conn)` — return a connection. Returns `:ok`. If a caller is blocked waiting, the returned connection is **validated before** being handed to the longest-waiting one; if it fails validation it is destroyed and a fresh connection is created for the waiter instead.

- `ValidatingPool.stats(name)` — return `%{available: a, in_use: u, total: t, max: max, min: min}` where `total == a + u`.

## Required behaviors

- **Validation on the way out.** No caller ever receives a connection that fails `:validate`. Invalid connections are destroyed (via `:destroy`) and do not count toward `total` afterward.
- **Lazy growth up to max**, distinct connections, and reuse of healthy returned connections.
- **Ownership monitoring / crash reclamation.** Monitor the checking-out process; if it dies while holding a connection, reclaim the connection (validating it before handing to any waiter).
- **Clean, server-side timeout.** A blocked `checkout` returns `{:error, :timeout}` as a normal value — implement the waiting/timeout logic in the server with a waiter queue and `Process.send_after` / `GenServer.reply`, not via `GenServer.call`'s own timeout.

Use only the OTP standard library — no external dependencies. Give me the complete module in a single file.