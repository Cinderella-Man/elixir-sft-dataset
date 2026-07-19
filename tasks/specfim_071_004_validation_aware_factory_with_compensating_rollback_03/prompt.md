# Write the missing @spec

Below is a complete, working module — except that the `@spec` for
`sequence/2` has been removed; its place is marked `# TODO: @spec`.
Write exactly that typespec: one `@spec` attribute for `sequence/2`,
consistent with the function's arguments, guards, and every return shape
the implementation can produce. Change nothing else.

## The module with the `@spec` for `sequence/2` missing

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
  # TODO: @spec
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

Give me only the `@spec` attribute — the attribute alone (however many
lines it spans), not the whole module.
