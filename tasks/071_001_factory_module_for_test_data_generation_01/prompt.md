# Specification: `Factory` — A Self-Contained Test Data Generation Module

## Overview

This document specifies an Elixir module called `Factory` that generates test data in the spirit of ExMachina, but simpler and self-contained.

Factory definitions are to be declared inside the `Factory` module using either a `define/2` macro or a `def factory(:name)` convention — the implementer picks whichever feels idiomatic.

At minimum, the module defines factories for `:user` (fields: `name`, `email`) and `:post` (fields: `title`, `body`, `user_id`).

The implementation uses only the Elixir standard library and assumes `Repo` is available as `MyApp.Repo`. Everything is delivered in a single file.

## API

The public API consists of the following functions:

- `Factory.build(factory_name)` — returns a struct for the named factory without touching the database.
- `Factory.build(factory_name, overrides)` — the same as above, but merges a keyword list of field overrides into the returned struct.
- `Factory.insert(factory_name)` — builds the struct and inserts it into the database via `Repo.insert!`, returning the persisted struct.
- `Factory.insert(factory_name, overrides)` — the same as above, with field overrides.
- `Factory.sequence(name, formatter_fn)` — returns the next value for a named sequence by calling `formatter_fn.(n)`, where `n` is a monotonically increasing integer starting at 1. Each call to `sequence/2` with the same `name` increments its own independent counter.
- `Factory.start/0` — starts the Agent that holds the sequence counters (see **Sequences and the Agent** below).

## Factory Behavior

### The `:user` factory

The default `name` and `email` must be non-empty strings. Every `build(:user)` must produce a distinct default `email`; this is driven through `sequence/2`.

### The `:post` factory

The `:post` factory must automatically call `Factory.insert(:user)` to create its association and populate `user_id`.

The general rule for associations: they are built eagerly on `Factory.build/1` only if they are embedded structs, but inserted (via `insert`) when they require a database ID.

## Sequences and the Agent

Sequence counters must be stored in a named `Agent`.

`Factory.start/0` starts this Agent. The test suite calls `Factory.start()` once during setup, so the function must be defined and must not crash if the Agent is already running. The implementation may additionally start the Agent lazily on first use.

Sequences must be unique across the entire test run even if tests run concurrently (`async: true`).

## Edge cases — association resolution contract

- Passing an explicit `user_id` override to `build(:post, ...)`/`insert(:post, ...)` suppresses the automatic `Factory.insert(:user)` association call entirely: `insert(:post, user_id: existing_id)` inserts exactly one record (the post itself) and creates no extra user.
- Conversely, `build(:post)` without a `user_id` override resolves the association eagerly at build time: it calls `Factory.insert(:user)`, persisting exactly one user record to the repo, and populates the built post's `user_id` with that user's integer id — even though the built post itself is not persisted.
