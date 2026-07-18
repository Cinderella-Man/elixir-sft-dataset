Write me an Elixir module called `Factory` that generates test data similarly to
ExMachina, but simpler and self-contained — with **trait composition** on top of
the basic build/insert API.

I need these functions in the public API:

- `Factory.build(factory_name)` — returns a struct for the named factory without
  touching the database.
- `Factory.build(factory_name, opts)` — `opts` is either a **keyword list of field
  overrides** (e.g. `name: "Ada"`) or a **list of trait atoms** (e.g. `[:admin]`).
  The module must figure out which one you meant: a proper keyword list is treated
  as overrides, a list of bare atoms as traits.
- `Factory.build(factory_name, traits, overrides)` — the explicit form: apply the
  named `traits` (a list of atoms) and then the `overrides` (a keyword list).
- `Factory.insert(factory_name)` / `insert(factory_name, opts)` /
  `insert(factory_name, traits, overrides)` — the same three shapes, but each
  persists the built struct via `MyApp.Repo.insert!` and returns the persisted
  struct (so its `id` field is a populated integer).
- `Factory.sequence(name, formatter_fn)` — returns the next value for a named
  sequence by calling `formatter_fn.(n)` where `n` is a monotonically increasing
  integer starting at 1. Each call with the same `name` increments its own
  independent counter. Sequences must stay unique across the whole test run even
  under concurrent (`async: true`) access, backed by a named `Agent`.

**Traits** are named, reusable overlays of field values, declared inside the
`Factory` module (e.g. a `def trait(factory_name, trait_name)` convention returning
a keyword list). Precedence, from lowest to highest, must be:
**factory defaults → traits (applied left to right) → explicit overrides.**
Requesting an unknown trait must raise `ArgumentError`.

At minimum define factories for:

- `:user` — fields `name`, `email`, `role` (default `"member"`), `active`
  (default `true`). Unless overridden, `name` and `email` are auto-populated with
  non-empty string values, and the generated `email` must be unique across builds
  (use `sequence/2` for this).
- `:post` — fields `title`, `body`, `user_id`. The `:post` factory must
  automatically call `Factory.insert(:user)` to create its association and
  populate `user_id` with the new user's integer `id` — even when building via
  `build/1` (no separate `insert`) — unless `user_id` is supplied as an override
  (in which case no user row is created).

Define at least these traits: `{:user, :admin}` (sets `role` to `"admin"`),
`{:user, :inactive}` (sets `active` to `false`), and `{:post, :published}` (sets a
`published` boolean field to `true`; `:post` defaults it to `false`).

Use only the Elixir standard library and assume `Repo` is available as
`MyApp.Repo`. Deliver everything in a single file.

## Additional interface contract

- The struct modules `MyApp.User` and `MyApp.Post` (with exactly the fields listed above) are provided by the test environment, just like `MyApp.Repo` — do NOT define `MyApp.User`, `MyApp.Post`, or `MyApp.Repo` in your file. Reference them (build with `struct/2`/`struct!/2`) and use `@compile {:no_warn_undefined, ...}` as needed so your single file compiles warning-free on its own.
- Define `Factory.start/0`: it starts the named `Agent` that backs the sequence counters and returns that `Agent.start_link/2` result. The test suite calls `Factory.start()` once (in `setup_all`) before using any other factory function.
