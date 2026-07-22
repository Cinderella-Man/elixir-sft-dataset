Write me an Elixir module called `Factory` that generates test data similarly to ExMachina, but simpler and self-contained.

I need these functions in the public API:

- `Factory.build(factory_name)` — returns a struct for the named factory without touching the database.
- `Factory.build(factory_name, overrides)` — same as above but merges a keyword list of field overrides into the returned struct.
- `Factory.insert(factory_name)` — builds the struct and inserts it into the database via `Repo.insert!`, returning the persisted struct.
- `Factory.insert(factory_name, overrides)` — same as above with field overrides.
- `Factory.sequence(name, formatter_fn)` — returns the next value for a named sequence by calling `formatter_fn.(n)` where `n` is a monotonically increasing integer starting at 1. Each call to `sequence/2` with the same `name` increments its own independent counter.

Factory definitions should be declared inside the `Factory` module using a `define/2` macro or a `def factory(:name)` convention — pick whichever feels idiomatic. At minimum, define factories for `:user` (fields: `name`, `email`) and `:post` (fields: `title`, `body`, `user_id`). The `:post` factory must automatically call `Factory.insert(:user)` to create its association and populate `user_id` — associations should be built eagerly on `Factory.build/1` only if they are embedded structs, but inserted (via `insert`) when they require a database ID.

Sequence counters must be stored in a named `Agent` that is started once (e.g., in `Factory.start/0` or automatically on first use via a lazy init). Sequences must be unique across the entire test run even if tests run concurrently (`async: true`).

Use only the Elixir standard library and assume `Repo` is available as `MyApp.Repo`. Deliver everything in a single file.

## Additional interface contract

- Passing an explicit `user_id` override to `build(:post, ...)`/`insert(:post, ...)` suppresses the automatic `Factory.insert(:user)` association call entirely: `insert(:post, user_id: existing_id)` inserts exactly one record (the post itself) and creates no extra user.
- Conversely, `build(:post)` without a `user_id` override resolves the association eagerly at build time: it calls `Factory.insert(:user)`, persisting exactly one user record to the repo, and populates the built post's `user_id` with that user's integer id — even though the built post itself is not persisted.