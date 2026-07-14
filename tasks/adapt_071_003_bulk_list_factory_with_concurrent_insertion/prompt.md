# Adapt existing code to a new specification

Below is a complete, working, tested Elixir solution to a related task. Do not
start from scratch: treat it as the codebase you have been asked to change.
Modify it to satisfy the new specification that follows — keep whatever carries
over, and change, add, or remove whatever the new specification requires.

Where the existing code and the new specification disagree (module name, public
API, behavior, constraints, output format), the new specification wins. Give me
the complete final result.

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

## Additional interface contract

- The struct modules `MyApp.User` and `MyApp.Post` (with exactly the fields listed above) are provided by the test environment, just like `MyApp.Repo` — do NOT define `MyApp.User`, `MyApp.Post`, or `MyApp.Repo` in your file. Reference them (build with `struct/2`/`struct!/2`) and use `@compile {:no_warn_undefined, ...}` as needed so your single file compiles warning-free on its own.
- Define `Factory.start/0`: it starts the named `Agent` that backs the sequence counters and returns that `Agent.start_link/2` result. The test suite calls `Factory.start()` once (in `setup_all`) before using any other factory function.
