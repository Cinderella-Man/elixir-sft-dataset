# Factory: Self-Contained Test Data Generation for Elixir

## Overview

This document specifies an Elixir module named `Factory` that generates test data in the spirit of
ExMachina, but simpler and self-contained — with first-class support for **bulk (list) generation**
and **params extraction**.

The implementation must rely on the Elixir standard library only, and may assume that `Repo` is
available as `MyApp.Repo`. Everything is delivered in a single file.

## API

The public API consists of the following functions.

- `Factory.build(factory_name)` / `build(factory_name, overrides)` — returns a struct for the named
  factory (merging a keyword list of field overrides), without touching the database.
- `Factory.insert(factory_name)` / `insert(factory_name, overrides)` — builds the struct and
  persists it via `MyApp.Repo.insert!`, returning the persisted struct.
- `Factory.build_list(count, factory_name)` / `build_list(count, factory_name, overrides)` —
  returns a list of `count` built structs. Each element is built independently, so sequence-driven
  fields (like default emails) stay unique across the list.
- `Factory.insert_list(count, factory_name)` / `insert_list(count, factory_name, overrides)` —
  persists `count` structs and returns the list of persisted structs. Insertion runs
  **concurrently** (one `Task` per record) while keeping every generated sequence value and every
  assigned id unique.
- `Factory.params_for(factory_name)` / `params_for(factory_name, overrides)` — returns a plain `map`
  of the factory's fields (not a struct) with the `:id` key removed, suitable for feeding into a
  request/changeset. Associations are still resolved to their persisted ids.
- `Factory.sequence(name, formatter_fn)` — returns the next value for a named sequence by calling
  `formatter_fn.(n)` where `n` is a monotonically increasing integer starting at 1. Each `name` has
  its own independent counter, and sequences remain unique across the whole test run even under
  concurrent (`async: true`) access, backed by a named `Agent`.
- `Factory.start/0` — starts the named `Agent` that backs the sequence counters and returns that
  `Agent.start_link/2` result. The test suite calls `Factory.start()` once (in `setup_all`) before
  using any other factory function.

## Factories

At minimum, factories are defined for `:user` (fields `name`, `email`) and `:post` (fields `title`,
`body`, `user_id`). The `:post` factory automatically calls `Factory.insert(:user)` to populate
`user_id`, unless `user_id` is supplied as an override.

## Interface contract

The struct modules `MyApp.User` and `MyApp.Post` (with exactly the fields listed above) are provided
by the test environment, just like `MyApp.Repo`. The delivered file must NOT define `MyApp.User`,
`MyApp.Post`, or `MyApp.Repo`. It references them instead (building with `struct/2`/`struct!/2`) and
uses `@compile {:no_warn_undefined, ...}` as needed so the single file compiles warning-free on its
own.

## Edge cases

- For `build_list`, a `count` of `0` returns `[]`.
- For `insert_list`, a `count` of `0` returns `[]`.
