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

  def build(name), do: build(name, [], [])

  def build(name, opts) when is_list(opts) do
    {traits, overrides} = split_opts(opts)
    build(name, traits, overrides)
  end

  def build(name, traits, overrides) when is_list(traits) and is_list(overrides) do
    trait_overlay = Enum.flat_map(traits, fn t -> trait(name, t) end)

    name
    |> factory()
    |> merge(trait_overlay)
    |> merge(overrides)
    |> resolve_thunks()
  end

  # -------------------------------------------------------------------------
  # insert
  # -------------------------------------------------------------------------

  def insert(name), do: insert(name, [], [])

  def insert(name, opts) when is_list(opts) do
    {traits, overrides} = split_opts(opts)
    insert(name, traits, overrides)
  end

  def insert(name, traits, overrides) when is_list(traits) and is_list(overrides) do
    name
    |> build(traits, overrides)
    |> MyApp.Repo.insert!()
  end

  # -------------------------------------------------------------------------
  # Internal helpers
  # -------------------------------------------------------------------------

  # A proper keyword list => overrides; anything else (list of atoms) => traits.
  defp split_opts(opts) do
    if Enum.all?(opts, &match?({key, _} when is_atom(key), &1)) do
      {[], opts}
    else
      {opts, []}
    end
  end

  defp merge(base, []), do: base
  defp merge(base, kw), do: struct(base, kw)

  # Resolve any zero-arity function fields (association thunks) that survived
  # merging. Overriding such a field replaces the thunk, suppressing its effect.
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

  defp ensure_agent_started do
    case Process.whereis(@agent) do
      nil -> Agent.start_link(fn -> %{} end, name: @agent)
      _pid -> :ok
    end
  end

  # -------------------------------------------------------------------------
  # Trait definitions
  # -------------------------------------------------------------------------

  defp trait(:user, :admin), do: [role: "admin"]
  defp trait(:user, :inactive), do: [active: false]
  defp trait(:post, :published), do: [published: true]

  defp trait(name, trait) do
    raise ArgumentError,
          "No trait #{inspect(trait)} defined for factory #{inspect(name)}."
  end

  # -------------------------------------------------------------------------
  # Factory definitions
  # -------------------------------------------------------------------------

  defp factory(:user) do
    struct!(MyApp.User,
      name: sequence(:user_name, &"User #{&1}"),
      email: sequence(:user_email, &"user-#{&1}@example.com"),
      role: "member",
      active: true
    )
  end

  defp factory(:post) do
    struct!(MyApp.Post,
      title: sequence(:post_title, &"Post title #{&1}"),
      body: sequence(:post_body, &"Post body #{&1}. Lorem ipsum dolor sit amet."),
      user_id: fn -> insert(:user).id end,
      published: false
    )
  end

  defp factory(name) do
    raise ArgumentError, "No factory defined for #{inspect(name)}."
  end
end
```
