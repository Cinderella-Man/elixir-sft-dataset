# Rework this solution for a changed brief

The module below is a complete, tested solution to a neighboring task. Treat
it as your starting codebase, not as a suggestion — carry over what still
fits and rewrite what the new brief demands. Where old code and the new
specification conflict (module name, public API, behavior, constraints,
output format), the new specification is authoritative. Return the complete
final result.

## Existing code (your starting point)

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
        next = Map.get(counters, name, 0) + 1
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

## New specification

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
