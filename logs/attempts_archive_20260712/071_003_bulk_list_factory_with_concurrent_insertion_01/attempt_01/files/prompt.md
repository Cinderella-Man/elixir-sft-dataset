Write me an Elixir module called `Factory` that generates test data similarly to
ExMachina, but simpler and self-contained — with first-class support for
**bulk (list) generation** and **params extraction**.

I need these functions in the public API:

- `Factory.build(factory_name)` / `build(factory_name, overrides)` — returns a
  struct for the named factory (merging a keyword list of field overrides),
  without touching the database.
- `Factory.insert(factory_name)` / `insert(factory_name, overrides)` — builds the
  struct and persists it via `MyApp.Repo.insert!`, returning the persisted struct.
- `Factory.build_list(count, factory_name)` /
  `build_list(count, factory_name, overrides)` — returns a list of `count` built
  structs. Each element must be built independently, so sequence-driven fields
  (like default emails) stay unique across the list. A `count` of `0` returns `[]`.
- `Factory.insert_list(count, factory_name)` /
  `insert_list(count, factory_name, overrides)` — persists `count` structs and
  returns the list of persisted structs. Insertion must run **concurrently** (one
  `Task` per record) while keeping every generated sequence value and every
  assigned id unique. A `count` of `0` returns `[]`.
- `Factory.params_for(factory_name)` /
  `params_for(factory_name, overrides)` — returns a plain `map` of the factory's
  fields (not a struct) with the `:id` key removed, suitable for feeding into a
  request/changeset. Associations are still resolved to their persisted ids.
- `Factory.sequence(name, formatter_fn)` — returns the next value for a named
  sequence by calling `formatter_fn.(n)` where `n` is a monotonically increasing
  integer starting at 1. Each `name` has its own independent counter, and
  sequences must remain unique across the whole test run even under concurrent
  (`async: true`) access, backed by a named `Agent`.

At minimum define factories for `:user` (fields `name`, `email`) and `:post`
(fields `title`, `body`, `user_id`). The `:post` factory must automatically call
`Factory.insert(:user)` to populate `user_id`, unless `user_id` is supplied as an
override.

Use only the Elixir standard library and assume `Repo` is available as
`MyApp.Repo`. Deliver everything in a single file.