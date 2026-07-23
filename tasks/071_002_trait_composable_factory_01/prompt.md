# Design brief: `Factory` — a self-contained test-data factory with trait composition

## Problem

Test suites need fixture data that is cheap to build, occasionally persisted, and
varied along a few named axes. ExMachina solves this, but we want something
simpler and self-contained: a single Elixir module called `Factory` that
generates test data similarly to ExMachina, with **trait composition** layered on
top of the basic build/insert API.

## Constraints

- Use only the Elixir standard library.
- Assume `Repo` is available as `MyApp.Repo`.
- Deliver everything in a single file.
- The struct modules `MyApp.User` and `MyApp.Post` (with exactly the fields
  listed below) are provided by the test environment, just like `MyApp.Repo` — do
  NOT define `MyApp.User`, `MyApp.Post`, or `MyApp.Repo` in your file. Reference
  them (build with `struct/2`/`struct!/2`) and use
  `@compile {:no_warn_undefined, ...}` as needed so your single file compiles
  warning-free on its own.
- **Traits** are named, reusable overlays of field values, declared inside the
  `Factory` module (e.g. a `def trait(factory_name, trait_name)` convention
  returning a keyword list).
- Value precedence, from lowest to highest, must be:
  **factory defaults → traits (applied left to right) → explicit overrides.**
- Requesting an unknown trait must raise `ArgumentError`.
- Sequences must stay unique across the whole test run even under concurrent
  (`async: true`) access, backed by a named `Agent`.

## Required interface

1. `Factory.build(factory_name)` — returns a struct for the named factory without
   touching the database.
2. `Factory.build(factory_name, opts)` — `opts` is either a **keyword list of
   field overrides** (e.g. `name: "Ada"`) or a **list of trait atoms**
   (e.g. `[:admin]`). The module must figure out which one you meant: a proper
   keyword list is treated as overrides, a list of bare atoms as traits.
3. `Factory.build(factory_name, traits, overrides)` — the explicit form: apply the
   named `traits` (a list of atoms) and then the `overrides` (a keyword list).
4. `Factory.insert(factory_name)` / `insert(factory_name, opts)` /
   `insert(factory_name, traits, overrides)` — the same three shapes, but each
   persists the built struct via `MyApp.Repo.insert!` and returns the persisted
   struct (so its `id` field is a populated integer).
5. `Factory.sequence(name, formatter_fn)` — returns the next value for a named
   sequence by calling `formatter_fn.(n)` where `n` is a monotonically increasing
   integer starting at 1. Each call with the same `name` increments its own
   independent counter.
6. `Factory.start/0` — starts the named `Agent` that backs the sequence counters
   and returns that `Agent.start_link/2` result. The test suite calls
   `Factory.start()` once (in `setup_all`) before using any other factory
   function.

## Required factories and traits

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

## Acceptance criteria

- All six interface entries above exist and behave exactly as described.
- Overrides-vs-traits disambiguation in the two-argument `build`/`insert` forms
  works as specified.
- Composition order is observably factory defaults, then traits left to right,
  then explicit overrides.
- An unknown trait raises `ArgumentError`.
- `insert` variants persist through `MyApp.Repo.insert!` and hand back the
  persisted struct with an integer `id`.
- Sequence values are unique for the whole test run under `async: true`.
- The file compiles warning-free on its own and defines none of `MyApp.User`,
  `MyApp.Post`, or `MyApp.Repo`.
