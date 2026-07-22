Write me an Elixir module called `DBCleaner` that gives integration tests **fine-grained, nested** rollback control using SQL savepoints layered on top of a single outer transaction.

The base "transaction" cleaner can only roll back the whole test. I want something richer: within one test I want to open named savepoints, roll back to a specific savepoint (undoing only the writes made after it), release savepoints, and finally discard everything when the test ends.

I need this public API:

- `DBCleaner.start(:savepoint, opts \\ [])` — called in a test's `setup` block. `opts` must include a `:repo` key (an Ecto repo module, e.g. `MyApp.Repo`). Begin an outer database transaction via `repo.begin_transaction/0` and initialize an empty savepoint stack. Store all state in the calling process's dictionary. Returns `{:ok, :savepoint}`.

- `DBCleaner.savepoint(name)` — issue `SAVEPOINT <name>` via `repo.query!(repo, sql, [])` and push `name` onto the stack. `name` must be a valid SQL identifier string (`/[a-zA-Z_][a-zA-Z0-9_]*/`). Returns `{:ok, name}`, or `{:error, :not_started}` if `start/2` was never called, or `{:error, {:invalid_name, name}}` for a bad identifier.

- `DBCleaner.rollback_to(name)` — issue `ROLLBACK TO SAVEPOINT <name>`. Per SQL semantics the savepoint itself survives but every savepoint created **after** it is discarded, so trim the stack to keep `name` and everything older. Returns `{:ok, name}`, or `{:error, {:no_such_savepoint, name}}` if it isn't on the stack.

- `DBCleaner.release(name)` — issue `RELEASE SAVEPOINT <name>`, which releases that savepoint and all savepoints created after it; pop them off the stack. Returns `{:ok, name}` or `{:error, {:no_such_savepoint, name}}`.

- `DBCleaner.active_savepoints()` — return the list of currently-active savepoint names, oldest first.

- `DBCleaner.clean()` — called in `on_exit`. Roll back the outer transaction via `repo.rollback/0`, discarding all test writes, and clear state. Safe no-op if `start/2` was never called.

Keep everything self-contained in a single file, no dependencies beyond Ecto, and use the process dictionary (`Process.put/get`) to carry state between calls so no extra process is required. Guard against SQL injection through savepoint names by validating identifiers.

Give me the complete module in a single file.