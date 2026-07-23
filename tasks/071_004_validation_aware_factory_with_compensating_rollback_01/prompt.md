**TICKET:** Implement `Factory`, a self-contained ExMachina-style test-data generator with validation and compensating rollback, so persistence has explicit success/failure semantics.

**Scope**
- Single Elixir module named `Factory`.
- Elixir standard library only.
- Deliver everything in a single file.
- Assume `Repo` is available as `MyApp.Repo`, providing `insert!/1` and `delete!/1`.

**Public API — build**
- `Factory.build(factory_name)` / `build(factory_name, overrides)`: returns a struct for the named factory, merging a keyword list of field overrides.
- Side effect: building a factory that has associations still creates the associated records, so their ids can be assigned.

**Public API — insert**
- `Factory.insert(factory_name)` / `insert(factory_name, overrides)`: builds the struct, validates its required fields, then:
  - success → persists via `MyApp.Repo.insert!` and returns `{:ok, persisted_struct}`;
  - failure → returns `{:error, {:missing_fields, list_of_field_atoms}}` and rolls back (deletes via `MyApp.Repo.delete!`) any association records that were auto-created while building the invalid parent, so a failed insert leaves the repo unchanged.
- `Factory.insert!(factory_name)` / `insert!(factory_name, overrides)`: same as `insert`, but returns the persisted struct on success and raises `ArgumentError` on validation failure.

**Public API — validation check**
- `Factory.valid?(factory_name, overrides \\ [])`: returns a boolean indicating whether the built struct passes validation.
- Must not leave stray association rows behind.

**Public API — sequences**
- `Factory.sequence(name, formatter_fn)`: returns the next value for a named sequence via `formatter_fn.(n)`.
- `n` is a monotonically increasing integer starting at 1.
- One independent counter per `name`.
- Values unique across the whole test run, including under concurrent (`async: true`) access.
- Backed by a named `Agent`.

**Public API — startup**
- `Factory.start/0`: starts the named `Agent` backing the sequence counters and returns that `Agent.start_link/2` result.
- Test suite calls `Factory.start()` once in `setup_all` before any other factory function.

**Factory definitions**
- Declare, per factory, which fields are required (must be non-`nil` for the struct to be valid).
- `:user` — fields `name`, `email`; both required.
- `:post` — fields `title`, `body`, `user_id`; all required.
- `:post` must automatically insert a `:user` to populate `user_id`, unless `user_id` is supplied as an override.
- If a `:post` insert fails validation, the auto-created user must be rolled back.

**Interface contract — provided modules**
- `MyApp.User` and `MyApp.Post` (with exactly the fields listed above) are provided by the test environment, as is `MyApp.Repo`.
- Do NOT define `MyApp.User`, `MyApp.Post`, or `MyApp.Repo` in your file.
- Reference them, building with `struct/2` / `struct!/2`.
- Use `@compile {:no_warn_undefined, ...}` as needed so the single file compiles warning-free on its own.
