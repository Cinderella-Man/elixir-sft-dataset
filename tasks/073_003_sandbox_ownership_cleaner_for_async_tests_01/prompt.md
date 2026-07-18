Write me an Elixir module called `DBCleaner` that provides an Ecto-Sandbox-style **ownership** model so that *asynchronous* integration tests can safely share sandboxed database connections across multiple processes.

The base transaction cleaner only works for `async: false` because all interaction must happen on the one process that owns the checked-out connection. I want the connection-ownership machinery that makes shared/allowed connections possible, tracked in a small named registry.

I need this public API:

- `DBCleaner.ensure_registry()` — start (or return the already-running) named ownership registry Agent. Idempotent. Returns `{:ok, pid}`.

- `DBCleaner.start(:sandbox, opts \\ [])` — called in `setup`. `opts` must include `:repo` (an Ecto repo module) and may include `:mode` which is `:manual` (default) or `:shared`. Check out a connection for the calling process via `repo.checkout/0` (returns a connection reference), register the caller as the **owner** of that connection, and in `:shared` mode also mark this owner as the global shared owner so any process resolves to it. Store per-process state in the process dictionary. Returns `{:ok, conn_ref}`.

- `DBCleaner.allow(owner_pid, allowed_pid)` — grant `allowed_pid` access to `owner_pid`'s connection (manual explicit-allowance mode). Returns `{:ok, allowed_pid}`, or `{:error, :no_owner}` if `owner_pid` doesn't currently own a connection.

- `DBCleaner.lookup(pid \\ self())` — resolve which connection serves `pid`, checking in order: is `pid` itself an owner, has `pid` been explicitly allowed onto an owner, or is there a global shared owner. Returns `{:ok, conn_ref}` or `:error`.

- `DBCleaner.clean()` — called in `on_exit`. Check the connection back in via `repo.checkin/1`, and remove this owner from the registry along with any allowances pointing at it and the shared marker if it was the shared owner. Returns `:ok`. Safe no-op (returning `:ok` without checking anything in) if `start/2` was never called or the connection has already been cleaned — a second `clean()` after a successful one must not check the same connection in twice.

Keep it self-contained in one file (no dependencies beyond Ecto). Per-process state goes in the process dictionary; the cross-process ownership map lives in a single named Agent. Model the registry state as `%{owners: %{pid => conn}, allow: %{allowed_pid => owner_pid}, shared: pid | nil}`.

Give me the complete module in a single file.
