# `DBCleaner` — savepoint-based nested rollback control for integration tests

Implement an Elixir module `DBCleaner` providing **fine-grained, nested** rollback control for integration tests, using SQL savepoints layered on top of a single outer transaction. The base "transaction" cleaner can only roll back the whole test; this variant must allow, within one test, opening named savepoints, rolling back to a specific savepoint (undoing only writes made after it), releasing savepoints, and discarding everything at test end.

**`DBCleaner.start(:savepoint, opts \\ [])`**
- Called from a test's `setup` block.
- `opts` must include a `:repo` key (an Ecto repo module, e.g. `MyApp.Repo`).
- Begins an outer database transaction via `repo.begin_transaction/0`.
- Initializes an empty savepoint stack.
- Stores all state in the calling process's dictionary.
- Returns `{:ok, :savepoint}`.

**`DBCleaner.savepoint(name)`**
- Issues `SAVEPOINT <name>` via `repo.query!(repo, sql, [])`.
- Pushes `name` onto the stack.
- `name` must be a valid SQL identifier string (`/[a-zA-Z_][a-zA-Z0-9_]*/`).
- Returns `{:ok, name}`.
- Returns `{:error, :not_started}` if `start/2` was never called.
- Returns `{:error, {:invalid_name, name}}` for a bad identifier.

**`DBCleaner.rollback_to(name)`**
- Issues `ROLLBACK TO SAVEPOINT <name>`.
- Per SQL semantics the savepoint itself survives while every savepoint created **after** it is discarded; trim the stack to keep `name` and everything older.
- Returns `{:ok, name}`.
- Returns `{:error, {:no_such_savepoint, name}}` if `name` isn't on the stack.

**`DBCleaner.release(name)`**
- Issues `RELEASE SAVEPOINT <name>`, releasing that savepoint and all savepoints created after it; pop them off the stack.
- Returns `{:ok, name}`.
- Returns `{:error, {:no_such_savepoint, name}}`.

**`DBCleaner.active_savepoints()`**
- Returns the list of currently-active savepoint names, oldest first.

**`DBCleaner.clean()`**
- Called from `on_exit`.
- Rolls back the outer transaction via `repo.rollback/0`, discarding all test writes, and clears state.
- Safe no-op if `start/2` was never called.

**Implementation constraints**
- Everything self-contained in a single file.
- No dependencies beyond Ecto.
- Use the process dictionary (`Process.put/get`) to carry state between calls, so no extra process is required.
- Guard against SQL injection through savepoint names by validating identifiers.

**Deliverable**
- The complete module in a single file.
