Implement `DBCleaner`: an Ecto-Sandbox-style **ownership** layer that lets `async` integration tests share sandboxed database connections across multiple processes.

**Background / motivation**
- The base transaction cleaner only works for `async: false`, because all interaction must happen on the single process that owns the checked-out connection.
- Required here: the connection-ownership machinery that makes shared/allowed connections possible, tracked in a small named registry.

**Public API — `DBCleaner.ensure_registry()`**
- Starts (or returns the already-running) named ownership registry Agent.
- Idempotent.
- Returns `{:ok, pid}`.

**Public API — `DBCleaner.start(:sandbox, opts \\ [])`**
- Called in `setup`.
- `opts` must include `:repo` (an Ecto repo module); may include `:mode`, which is `:manual` (default) or `:shared`.
- Checks out a connection for the calling process via `repo.checkout/0` (returns a connection reference).
- Registers the caller as the **owner** of that connection.
- In `:shared` mode, additionally marks this owner as the global shared owner, so any process resolves to it.
- Stores per-process state in the process dictionary.
- Returns `{:ok, conn_ref}`.

**Public API — `DBCleaner.allow(owner_pid, allowed_pid)`**
- Grants `allowed_pid` access to `owner_pid`'s connection (manual explicit-allowance mode).
- Returns `{:ok, allowed_pid}`.
- Returns `{:error, :no_owner}` if `owner_pid` doesn't currently own a connection.

**Public API — `DBCleaner.lookup(pid \\ self())`**
- Resolves which connection serves `pid`, checking in this order: (1) is `pid` itself an owner, (2) has `pid` been explicitly allowed onto an owner, (3) is there a global shared owner.
- Returns `{:ok, conn_ref}` or `:error`.

**Public API — `DBCleaner.clean()`**
- Called in `on_exit`.
- Checks the connection back in via `repo.checkin/1`.
- Removes this owner from the registry, along with any allowances pointing at it, and the shared marker if it was the shared owner.
- Returns `:ok`.
- Safe no-op (returns `:ok` without checking anything in) when `start/2` was never called or the connection has already been cleaned; a second `clean()` after a successful one must not check the same connection in twice.

**Implementation constraints**
- Self-contained in one file; no dependencies beyond Ecto.
- Per-process state goes in the process dictionary.
- The cross-process ownership map lives in a single named Agent.
- Registry state modeled as `%{owners: %{pid => conn}, allow: %{allowed_pid => owner_pid}, shared: pid | nil}`.

**Deliverable**
- The complete module in a single file.
