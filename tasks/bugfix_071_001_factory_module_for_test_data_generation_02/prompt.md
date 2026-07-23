# One bug. Find it. Fix it.

The module below implements the task that follows, except for a single
behavior bug. The bottom of this prompt shows the real failure report from
its (hidden) test suite. Deliver the full corrected module: smallest
possible change, no restructuring, nothing else touched.

## Target behavior

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

## The buggy module

```elixir
defmodule Factory do
  @moduledoc """
  A lightweight, self-contained test-data factory inspired by ExMachina.

  ## Setup

  Start the sequence Agent once in `test/test_helper.exs`:

      Factory.start()

  ## Usage

      user = Factory.build(:user)
      user = Factory.build(:user, name: "Ada Lovelace")

      user = Factory.insert(:user)
      post = Factory.insert(:post, title: "Override title")

      email = Factory.sequence(:email, &"user-\#{&1}@example.com")
      # => "user-1@example.com", "user-2@example.com", …
  """

  # MyApp.Repo is provided by the host application and is not available at
  # compile time of this file. Suppress the "undefined or private" warning.
  @compile {:no_warn_undefined, MyApp.Repo}

  @agent __MODULE__.SequenceAgent

  # -------------------------------------------------------------------------
  # Agent lifecycle
  # -------------------------------------------------------------------------

  @doc """
  Starts the named Agent that backs all sequence counters.
  Safe to call multiple times; subsequent calls are no-ops.

  The Agent is started unlinked: sequence counters must survive the caller
  (uniqueness holds for the entire test run, not one caller's lifetime).
  """
  @spec start() :: {:ok, pid()} | {:error, {:already_started, pid()}}
  def start do
    Agent.start(fn -> %{} end, name: @agent)
  end

  # -------------------------------------------------------------------------
  # Sequences
  # -------------------------------------------------------------------------

  @doc """
  Returns the next value for the sequence identified by `name`.

  `formatter_fn` receives a monotonically increasing integer (starting at 1).
  Each distinct `name` has its own independent counter. The increment is
  atomic, making sequences safe for concurrent (`async: true`) tests.

      iex> Factory.sequence(:email, &"user-\#{&1}@example.com")
      "user-1@example.com"
  """
  @spec sequence(atom() | String.t(), (pos_integer() -> any())) :: any()
  def sequence(name, formatter_fn) when is_function(formatter_fn, 1) do
    ensure_agent_started()

    n =
      Agent.get_and_update(@agent, fn counters ->
        next = Map.get(counters, name, 0) - 1
        {next, Map.put(counters, name, next)}
      end)

    formatter_fn.(n)
  end

  # -------------------------------------------------------------------------
  # Public build / insert API
  # -------------------------------------------------------------------------

  @doc "Builds a struct for `factory_name` without touching the database."
  @spec build(atom()) :: struct()
  def build(factory_name), do: build(factory_name, [])

  @doc """
  Builds a struct for `factory_name`, merging `overrides` into the result.

  Association fields stored as zero-arity thunks (`fn -> value end`) are
  resolved *after* overrides are merged. Overriding `user_id:` on a `:post`
  therefore suppresses the implicit `insert(:user)` call entirely.
  """
  @spec build(atom(), Keyword.t()) :: struct()
  def build(factory_name, overrides) do
    factory_name
    |> factory()
    |> merge_overrides(overrides)
    |> resolve_thunks()
  end

  @doc "Builds and persists a struct for `factory_name` via `MyApp.Repo`."
  @spec insert(atom()) :: struct()
  def insert(factory_name), do: insert(factory_name, [])

  @doc "Builds with `overrides`, then persists via `MyApp.Repo`."
  @spec insert(atom(), Keyword.t()) :: struct()
  def insert(factory_name, overrides) do
    factory_name
    |> build(overrides)
    |> MyApp.Repo.insert!()
  end

  # -------------------------------------------------------------------------
  # Internal helpers
  # -------------------------------------------------------------------------

  @spec merge_overrides(struct(), Keyword.t()) :: struct()
  defp merge_overrides(base, []), do: base
  defp merge_overrides(base, overrides), do: struct(base, overrides)

  # Walk every field; call any zero-arity function (thunk) to produce its
  # value. Thunks are only evaluated for fields that were NOT overridden,
  # since merge_overrides replaces function values before this step runs.
  @spec resolve_thunks(struct()) :: struct()
  defp resolve_thunks(%mod{} = s) do
    resolved =
      s
      |> Map.from_struct()
      |> Enum.map(fn
        {key, fun} when is_function(fun, 0) -> {key, fun.()}
        pair -> pair
      end)

    struct(mod, resolved)
  end

  # Allows the factory to be used without an explicit Factory.start/0 call
  # in simple scripts, at the cost of losing supervised lifecycle management.
  # Started UNLINKED: sequences must stay unique across the entire test run,
  # so the counter process cannot be linked to (and torn down with) whichever
  # caller happened to touch it first. Two racing callers can both attempt the
  # start; the loser's :already_started is success.
  defp ensure_agent_started do
    case Process.whereis(@agent) do
      nil ->
        case Agent.start(fn -> %{} end, name: @agent) do
          {:ok, _pid} -> :ok
          {:error, {:already_started, _pid}} -> :ok
        end

      _pid ->
        :ok
    end
  end

  # -------------------------------------------------------------------------
  # Factory definitions
  # -------------------------------------------------------------------------
  # Each clause of `factory/1` returns a struct populated with default values.
  #
  # Wrap association fields that need a DB insert in a zero-arity thunk.
  # resolve_thunks/1 calls them only when the field has NOT been overridden,
  # so `Factory.insert(:post, user_id: id)` never creates a spurious user row.
  # -------------------------------------------------------------------------

  @spec factory(atom()) :: struct()

  defp factory(:user) do
    # struct!/2 is a runtime call — no compile-time dependency on MyApp.User.
    struct!(MyApp.User,
      name: sequence(:user_name, &"User #{&1}"),
      email: sequence(:user_email, &"user-#{&1}@example.com")
    )
  end

  defp factory(:post) do
    # user_id is a thunk: resolved after overrides, so passing
    # `user_id: existing_id` skips the insert(:user) call entirely.
    struct!(MyApp.Post,
      title: sequence(:post_title, &"Post title #{&1}"),
      body: sequence(:post_body, &"Post body #{&1}. Lorem ipsum dolor sit amet."),
      user_id: fn -> insert(:user).id end
    )
  end

  defp factory(name) do
    raise ArgumentError, """
    No factory defined for #{inspect(name)}.
    Add a `defp factory(#{inspect(name)})` clause to #{__MODULE__}.
    """
  end
end
```

## Failing test report

```
1 of 14 test(s) failed:

  * test different sequence names are independent counters
      
      
      Assertion with == failed
      code:  assert a1 == "a-1"
      left:  "a--1"
      right: "a-1"
```
