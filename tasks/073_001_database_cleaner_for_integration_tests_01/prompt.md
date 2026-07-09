Write me an Elixir module called `DBCleaner` that ensures database isolation between integration tests by cleaning up state between test runs.

I need these functions in the public API:
- `DBCleaner.start(strategy, opts \\ [])` — called in a test's `setup` block. The `strategy` is either `:transaction` or `:truncation`. The `opts` keyword list should accept a `:repo` key (an Ecto repo module, e.g. `MyApp.Repo`) and a `:tables` key (a list of table name strings to truncate, e.g. `["users", "posts"]`). Store whatever state is needed to clean up later.
- `DBCleaner.clean()` — called in `on_exit`. Performs the actual cleanup based on whichever strategy was started.

Implement two strategies:

**`:transaction`** — In `start/2`, begin a database transaction (using `Ecto.Adapters.SQL.begin_transaction/1` or equivalent) and store the connection/transaction reference in the process dictionary or a named Agent. In `clean/0`, roll back that transaction so no data persists. This strategy is fast but only works with synchronous tests (`async: false`).

**`:truncation`** — `start/2` performs no database work: it only validates the table names and stashes the `:repo` and `:tables` options in the process dictionary so `clean/0` can retrieve them. In `clean/0`, issue a `TRUNCATE <table> RESTART IDENTITY CASCADE` SQL command for every table listed in `:tables`, executed via `Ecto.Adapters.SQL.query!/3`. This strategy is slower but works with any test configuration.

Both strategies should be entirely self-contained in a single file with no external dependencies beyond Ecto. Use the process dictionary (`Process.put/get`) to carry state between `start/2` and `clean/0` so no extra process is required.

Give me the complete module in a single file.

## Additional interface contract

- Under the `:truncation` strategy, `clean/0` issues exactly one SQL statement per listed table (never a single combined multi-table `TRUNCATE`), each of the exact form `TRUNCATE <table> RESTART IDENTITY CASCADE` with the bare, unquoted table name. Execute it by calling `query!/3` on the configured repo module itself — `repo.query!(repo, sql, [])` — rather than referencing `Ecto.Adapters.SQL` directly, so a stand-in repo module that defines `query!/3` receives one call per table.
- The same stand-in-repo rule applies to the `:transaction` strategy: `start/2` must begin the transaction eagerly, during `start/2` itself (not deferred to `clean/0`), by calling `begin_transaction/0` with no arguments on the configured repo module — `repo.begin_transaction()`. Do not call `Ecto.Adapters.SQL.begin_transaction(repo)`, `repo.transaction/1`, `repo.checkout/1`, or anything that touches `get_dynamic_repo/0`; the "`Ecto.Adapters.SQL.begin_transaction/1` or equivalent" wording above means the repo-module call is the required equivalent here. The call returns `{:ok, ref}` — the ref may be stored or simply discarded.
- Under the `:transaction` strategy, `clean/0` rolls back by calling `rollback/0` with no arguments on the repo module — `repo.rollback()` — and must issue no SQL at all via `query!/3`. The `:tables` option is accepted but ignored entirely by this strategy: no `TRUNCATE` statement may be issued even when tables were passed to `start/2`.
- `clean/0` when `start/2` was never called must be a safe no-op that returns `:ok` — it must not exit or crash the calling process.
- Every `start/2` call fully replaces any previously stored strategy state, so consecutive start/clean cycles in the same process never bleed into each other: a `:truncation` cycle followed by a `:transaction` cycle must not produce any `TRUNCATE` query during the second cycle's `clean/0`.