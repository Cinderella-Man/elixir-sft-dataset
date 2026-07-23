# Migrate existing code to a new spec

Starting point: the working, tested solution below, from a related task.
Change it — no ground-up rewrite — until it satisfies the specification
that follows. On any disagreement between the two (module name, public API,
behavior, constraints, output format), the new specification wins. Output
the complete updated code.

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
