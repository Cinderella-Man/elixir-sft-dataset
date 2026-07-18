Write me an Elixir module called `Factory` that generates test data similarly to
ExMachina, but simpler and self-contained — with **validation and compensating
rollback** so persistence has explicit success/failure semantics.

I need these functions in the public API:

- `Factory.build(factory_name)` / `build(factory_name, overrides)` — returns a
  struct for the named factory (merging a keyword list of field overrides). As a
  side effect, building a factory that has associations still creates the
  associated records (so their ids can be assigned).
- `Factory.insert(factory_name)` / `insert(factory_name, overrides)` — builds the
  struct, **validates** its required fields, and:
  - on success, persists it via `MyApp.Repo.insert!` and returns
    `{:ok, persisted_struct}`;
  - on failure, returns `{:error, {:missing_fields, list_of_field_atoms}}` **and
    rolls back (deletes via `MyApp.Repo.delete!`) any association records that were
    auto-created while building the invalid parent**, so a failed insert leaves the
    repo unchanged.
- `Factory.insert!(factory_name)` / `insert!(factory_name, overrides)` — same as
  `insert`, but returns the persisted struct on success and raises `ArgumentError`
  on validation failure.
- `Factory.valid?(factory_name, overrides \\ [])` — returns a boolean indicating
  whether the built struct passes validation (it must not leave stray association
  rows behind).
- `Factory.sequence(name, formatter_fn)` — returns the next value for a named
  sequence via `formatter_fn.(n)` with `n` a monotonically increasing integer
  starting at 1, one independent counter per `name`, unique across the whole test
  run even under concurrent (`async: true`) access, backed by a named `Agent`.

Declare, per factory, which fields are **required** (must be non-`nil` for the
struct to be valid). At minimum define factories for `:user` (fields `name`,
`email`; both required) and `:post` (fields `title`, `body`, `user_id`; all
required). The `:post` factory must automatically insert a `:user` to populate
`user_id`, unless `user_id` is supplied as an override — and if a `:post` insert
fails validation, the auto-created user must be rolled back.

Use only the Elixir standard library and assume `Repo` is available as
`MyApp.Repo` (providing `insert!/1` and `delete!/1`). Deliver everything in a
single file.