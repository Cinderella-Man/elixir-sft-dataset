Write me an Elixir module called `DBCleaner` that cleans integration-test tables using ordered `DELETE FROM` statements that respect **foreign-key dependencies**, rather than `TRUNCATE ... CASCADE`.

`TRUNCATE ... CASCADE` is a blunt instrument — it can silently wipe tables you didn't list, and some setups disallow it. I want a cleaner that deletes rows in dependency order: a child table (one holding a foreign key) is emptied *before* the parent table it references, so no FK constraint is ever violated. That order must be derived by topologically sorting a dependency spec.

I need this public API:

- `DBCleaner.start(:deletion, opts \\ [])` — called in `setup`. `opts` must include `:repo` (an Ecto repo module) and `:tables`, a list describing the tables and their dependencies. Each entry is either a plain table-name string `"users"` (no dependencies) or a tuple `{"comments", ["posts"]}` meaning the `comments` table has a foreign key into `posts` (so `comments` must be deleted first). Validate every table/dependency name against `/[a-zA-Z_][a-zA-Z0-9_]*/` (raise `ArgumentError` on a bad name). This function issues no SQL; it just stores the normalized spec in the process dictionary. Returns `{:ok, :deletion}`.

- `DBCleaner.deletion_order(spec)` — a pure helper that takes a normalized spec map `%{table => [dependency, ...]}` and returns `{:ok, ordered_tables}` where each table precedes the tables it depends on (children first, parents last). Dependencies that reference tables not in the map are ignored for ordering. If the dependencies contain a cycle, return `{:error, {:cycle, remaining_tables}}` where `remaining_tables` is the sorted list of the tables still involved in the cycle. The order must be deterministic (break ties by sorting names).

- `DBCleaner.clean()` — called in `on_exit`. Compute the deletion order, then issue `DELETE FROM <table>` via `repo.query!(repo, sql, [])` for each table in that order. On success return `:ok` (not the ordered table list). On a cycle, issue no queries and return `{:error, {:cycle, ...}}`. Safe no-op returning `:ok` if `start/2` was never called.

Keep it self-contained in one file (no dependencies beyond Ecto), store state in the process dictionary, and implement the topological sort yourself (e.g. Kahn's algorithm). Guard against SQL injection via the identifier allowlist.

Give me the complete module in a single file.
