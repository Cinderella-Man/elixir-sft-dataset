Write me an Elixir module called `DBCleaner` that ensures database isolation between integration tests by cleaning up state between test runs.

I need these functions in the public API:
- `DBCleaner.start(strategy, opts \\ [])` — called in a test's `setup` block. The `strategy` is either `:transaction` or `:truncation`. The `opts` keyword list should accept a `:repo` key (an Ecto repo module, e.g. `MyApp.Repo`) and a `:tables` key (a list of table name strings to truncate, e.g. `["users", "posts"]`). Store whatever state is needed to clean up later.
- `DBCleaner.clean()` — called in `on_exit`. Performs the actual cleanup based on whichever strategy was started.

Implement two strategies:

**`:transaction`** — In `start/2`, begin a database transaction (using `Ecto.Adapters.SQL.begin_transaction/1` or equivalent) and store the connection/transaction reference in the process dictionary or a named Agent. In `clean/0`, roll back that transaction so no data persists. This strategy is fast but only works with synchronous tests (`async: false`).

**`:truncation`** — `start/2` is a no-op (nothing to set up). In `clean/0`, issue a `TRUNCATE <table> RESTART IDENTITY CASCADE` SQL command for every table listed in `:tables`, executed via `Ecto.Adapters.SQL.query!/3`. This strategy is slower but works with any test configuration.

Both strategies should be entirely self-contained in a single file with no external dependencies beyond Ecto. Use the process dictionary (`Process.put/get`) to carry state between `start/2` and `clean/0` so no extra process is required.

Give me the complete module in a single file.