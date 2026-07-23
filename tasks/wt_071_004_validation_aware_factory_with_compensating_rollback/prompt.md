# Write the test harness

Module and original specification below. Produce the ExUnit harness that
verifies a correct implementation.

Hard requirements:
- Test module: `<Module>Test`, `use ExUnit.Case, async: false`.
- No `ExUnit.start()` (the evaluator owns startup).
- Self-contained single file: inline any fakes, clock Agents, and helpers.
- Full public API coverage plus the specification's edge cases.
- Compiles with zero warnings (`_`-prefix unused variables; float zero
  matches as `+0.0`/`-0.0`).

## Original specification

Write me an Elixir module called `Factory` that generates test data similarly to
ExMachina, but simpler and self-contained — with **validation and compensating
rollback** so persistence has explicit success/failure semantics.

I need these functions in the public API:

- `Factory.build(factory_name)` / `build(factory_name, overrides)` — returns a
  struct for the named factory (merging a keyword list of field overrides). As a
  side effect, building a factory that has associations still creates the
  associated records (so their ids can be assigned).
- `Factory.insert(factory_name)` / `insert(factory_name, overrides)` — builds the
  struct, **validates** its required fields, and:
  - on success, persists it via `MyApp.Repo.insert!` and returns
    `{:ok, persisted_struct}`;
  - on failure, returns `{:error, {:missing_fields, list_of_field_atoms}}` **and
    rolls back (deletes via `MyApp.Repo.delete!`) any association records that were
    auto-created while building the invalid parent**, so a failed insert leaves the
    repo unchanged.
- `Factory.insert!(factory_name)` / `insert!(factory_name, overrides)` — same as
  `insert`, but returns the persisted struct on success and raises `ArgumentError`
  on validation failure.
- `Factory.valid?(factory_name, overrides \\ [])` — returns a boolean indicating
  whether the built struct passes validation (it must not leave stray association
  rows behind).
- `Factory.sequence(name, formatter_fn)` — returns the next value for a named
  sequence via `formatter_fn.(n)` with `n` a monotonically increasing integer
  starting at 1, one independent counter per `name`, unique across the whole test
  run even under concurrent (`async: true`) access, backed by a named `Agent`.

Declare, per factory, which fields are **required** (must be non-`nil` for the
struct to be valid). At minimum define factories for `:user` (fields `name`,
`email`; both required) and `:post` (fields `title`, `body`, `user_id`; all
required). The `:post` factory must automatically insert a `:user` to populate
`user_id`, unless `user_id` is supplied as an override — and if a `:post` insert
fails validation, the auto-created user must be rolled back.

Use only the Elixir standard library and assume `Repo` is available as
`MyApp.Repo` (providing `insert!/1` and `delete!/1`). Deliver everything in a
single file.

## Additional interface contract

- The struct modules `MyApp.User` and `MyApp.Post` (with exactly the fields listed above) are provided by the test environment, just like `MyApp.Repo` — do NOT define `MyApp.User`, `MyApp.Post`, or `MyApp.Repo` in your file. Reference them (build with `struct/2`/`struct!/2`) and use `@compile {:no_warn_undefined, ...}` as needed so your single file compiles warning-free on its own.
- Define `Factory.start/0`: it starts the named `Agent` that backs the sequence counters and returns that `Agent.start_link/2` result. The test suite calls `Factory.start()` once (in `setup_all`) before using any other factory function.

## Module under test

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
        {:ok, MyApp.Repo.insert!(struct)}

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
