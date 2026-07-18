# Document this module

Below is a complete, working, tested Elixir module. Its behavior is correct
and must not change — but every piece of documentation has been stripped.

Add the missing documentation and typespecs:

- a `@moduledoc` that explains what the module does and how it is used,
- a `@doc` for every public function,
- a `@spec` for every public function (add `@type`s where they make the
  specs clearer).

Do not change any behavior: every function clause, guard, and expression
must keep working exactly as it does now. Do not rename anything, do not
"improve" the code, and do not add or remove functions. Give me the
complete documented module in a single file.

## The module

```elixir
defmodule Factory do
  @compile {:no_warn_undefined, MyApp.Repo}

  @agent __MODULE__.SequenceAgent

  # -------------------------------------------------------------------------
  # Agent lifecycle + sequences
  # -------------------------------------------------------------------------

  def start do
    Agent.start_link(fn -> %{} end, name: @agent)
  end

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

  def build(name), do: build(name, [])

  def build(name, overrides) do
    {struct, _assocs} = build_with_assocs(name, overrides)
    struct
  end

  # -------------------------------------------------------------------------
  # insert / insert! with validation + compensation
  # -------------------------------------------------------------------------

  def insert(name), do: insert(name, [])

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

  def insert!(name), do: insert!(name, [])

  def insert!(name, overrides) do
    case insert(name, overrides) do
      {:ok, struct} ->
        struct

      {:error, reason} ->
        raise ArgumentError,
              "insert!/2 failed for #{inspect(name)}: #{inspect(reason)}"
    end
  end

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
