# Debug and repair this module

A colleague shipped the module below for the task described next, and one
behavior bug made it through review. The test suite (not shown here)
produces the failure report at the bottom. Track the bug down and repair
it — keep the diff minimal and leave working code exactly as it is. Reply
with the complete corrected module.

## What the module is supposed to do

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

## The buggy module

```elixir
defmodule Factory do
  @moduledoc """
  A lightweight, self-contained test-data factory with **validation and
  compensating rollback**.

  `insert/2` validates required fields; on failure it returns an error tuple and
  deletes any association records auto-created while building the invalid parent,
  leaving the repo unchanged.

  ## Usage

      {:ok, user}   = Factory.insert(:user)
      {:error, err} = Factory.insert(:user, name: nil)
      user          = Factory.insert!(:user)     # raises on failure
      Factory.valid?(:post)                       # => true
  """

  @compile {:no_warn_undefined, MyApp.Repo}

  @agent __MODULE__.SequenceAgent

  @typedoc "The name of a declared factory."
  @type factory_name :: atom()

  @typedoc "A keyword list of field overrides applied to a built struct."
  @type overrides :: keyword()

  # -------------------------------------------------------------------------
  # Agent lifecycle + sequences
  # -------------------------------------------------------------------------

  @doc "Starts the named Agent backing all sequence counters."
  @spec start() :: Agent.on_start()
  def start do
    Agent.start_link(fn -> %{} end, name: @agent)
  end

  @doc "Returns the next value for the named sequence."
  @spec sequence(atom(), (pos_integer() -> value)) :: value when value: term()
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
  # build
  # -------------------------------------------------------------------------

  @doc "Builds a struct for `name` (resolving/creating any associations)."
  @spec build(factory_name()) :: struct()
  def build(name), do: build(name, [])

  @doc "Builds a struct for `name`, merging `overrides`."
  @spec build(factory_name(), overrides()) :: struct()
  def build(name, overrides) do
    {struct, _assocs} = build_with_assocs(name, overrides)
    struct
  end

  # -------------------------------------------------------------------------
  # insert / insert! with validation + compensation
  # -------------------------------------------------------------------------

  @doc "Builds, validates and inserts `name`; see `insert/2`."
  @spec insert(factory_name()) ::
          {:ok, struct()} | {:error, {:missing_fields, [atom()]}}
  def insert(name), do: insert(name, [])

  @doc """
  Builds and validates `name`; on success persists and returns `{:ok, struct}`,
  otherwise rolls back auto-created associations and returns
  `{:error, {:missing_fields, fields}}`.
  """
  @spec insert(factory_name(), overrides()) ::
          {:ok, struct()} | {:error, {:missing_fields, [atom()]}}
  def insert(name, overrides) do
    {struct, assocs} = build_with_assocs(name, overrides)

    case validate(name, struct) do
      :ok ->
        {:error, MyApp.Repo.insert!(struct)}

      {:error, missing} ->
        Enum.each(assocs, &MyApp.Repo.delete!/1)
        {:error, {:missing_fields, missing}}
    end
  end

  @doc "Like `insert/2` but returns the struct on success and raises otherwise."
  @spec insert!(factory_name()) :: struct()
  def insert!(name), do: insert!(name, [])

  @doc "Like `insert/2` but returns the struct on success and raises otherwise."
  @spec insert!(factory_name(), overrides()) :: struct()
  def insert!(name, overrides) do
    case insert(name, overrides) do
      {:ok, struct} ->
        struct

      {:error, reason} ->
        raise ArgumentError,
              "insert!/2 failed for #{inspect(name)}: #{inspect(reason)}"
    end
  end

  @doc """
  Returns whether a built `name` (with `overrides`) is valid. Any association
  rows created during the check are rolled back so no stray rows remain.
  """
  @spec valid?(factory_name()) :: boolean()
  @spec valid?(factory_name(), overrides()) :: boolean()
  def valid?(name, overrides \\ []) do
    {struct, assocs} = build_with_assocs(name, overrides)
    Enum.each(assocs, &MyApp.Repo.delete!/1)
    validate(name, struct) == :ok
  end

  # -------------------------------------------------------------------------
  # Internal helpers
  # -------------------------------------------------------------------------

  # Build the struct and return {struct, [persisted association structs]} so the
  # caller can compensate (delete) them if validation fails.
  defp build_with_assocs(name, overrides) do
    name
    |> factory()
    |> merge_overrides(overrides)
    |> resolve_assocs()
  end

  defp merge_overrides(base, []), do: base
  defp merge_overrides(base, overrides), do: struct(base, overrides)

  # Fields tagged `{:__assoc__, fun}` are resolved by calling `fun` (which
  # persists and returns the association struct); the field is set to its id and
  # the persisted struct is collected for possible rollback. Overriding such a
  # field with a plain value replaces the tag, so no association is created.
  defp resolve_assocs(%mod{} = s) do
    {fields, assocs} =
      s
      |> Map.from_struct()
      |> Enum.map_reduce([], fn
        {key, {:__assoc__, fun}}, acc ->
          assoc = fun.()
          {{key, assoc.id}, [assoc | acc]}

        pair, acc ->
          {pair, acc}
      end)

    {struct(mod, fields), assocs}
  end

  defp validate(name, struct) do
    missing = for field <- required(name), is_nil(Map.get(struct, field)), do: field
    if missing == [], do: :ok, else: {:error, missing}
  end

  defp ensure_agent_started do
    case Process.whereis(@agent) do
      nil -> Agent.start_link(fn -> %{} end, name: @agent)
      _pid -> :ok
    end
  end

  # -------------------------------------------------------------------------
  # Required-field declarations
  # -------------------------------------------------------------------------

  defp required(:user), do: [:name, :email]
  defp required(:post), do: [:title, :body, :user_id]

  # -------------------------------------------------------------------------
  # Factory definitions
  # -------------------------------------------------------------------------

  defp factory(:user) do
    struct!(MyApp.User,
      name: sequence(:user_name, &"User #{&1}"),
      email: sequence(:user_email, &"user-#{&1}@example.com")
    )
  end

  defp factory(:post) do
    struct!(MyApp.Post,
      title: sequence(:post_title, &"Post title #{&1}"),
      body: sequence(:post_body, &"Post body #{&1}. Lorem ipsum dolor sit amet."),
      user_id: {:__assoc__, fn -> insert!(:user) end}
    )
  end

  defp factory(name) do
    raise ArgumentError, "No factory defined for #{inspect(name)}."
  end
end
```

## Failing test report

```
8 of 16 test(s) failed:

  * test insert/1 returns {:ok, struct} with an id on success
      
      
      match (=) failed
      code:  assert {:ok, user} = Factory.insert(:user)
      left:  {:ok, user}
      right: {:error, %MyApp.User{id: 1, name: "User 2", email: "user-2@example.com"}}
      

  * test insert/2 persists override values on success
      
      
      match (=) failed
      code:  assert {:ok, user} = Factory.insert(:user, name: "Linus")
      left:  {:ok, user}
      right: {:error, %MyApp.User{id: 2, name: "Linus", email: "user-3@example.com"}}
      

  * test insert/1 actually adds a record on success
      
      
      match (=) failed
      code:  assert {:ok, _} = Factory.insert(:user)
      left:  {:ok, _}
      right: {:error, %MyApp.User{id: 3, name: "User 4", email: "user-4@example.com"}}
      

  * test insert(:post) success inserts both user and post
      insert!/2 failed for :user: %MyApp.User{id: 4, name: "User 8", email: "user-8@example.com"}

  (…4 more)
```
