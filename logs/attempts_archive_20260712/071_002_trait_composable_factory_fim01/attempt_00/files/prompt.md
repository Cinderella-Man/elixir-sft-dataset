Implement the public `build/3` function — the explicit three-argument form
`build(name, traits, overrides)`, guarded by
`when is_list(traits) and is_list(overrides)`.

It receives a factory `name` (atom), a list of `traits` (atoms), and a keyword
list of `overrides`. It must build a struct honoring the precedence
**factory defaults → traits (applied left to right) → explicit overrides**, and
then resolve any association thunks.

Concretely, it should:

1. Compute a single `trait_overlay` keyword list by flat-mapping over `traits`,
   calling `trait(name, t)` for each trait `t` (so traits are applied in order,
   left to right, and an unknown trait raises `ArgumentError` via `trait/2`).
2. Start from the factory defaults returned by `factory(name)`, then `merge/2`
   the `trait_overlay`, then `merge/2` the `overrides` (each `merge/2` layers the
   keyword values over the struct via `struct/2`, so later layers win).
3. Finally pass the merged struct through `resolve_thunks/1` so any zero-arity
   function fields (e.g. the `:post` factory's `user_id` association) are
   evaluated — unless they were replaced by an override, in which case no thunk
   runs.

Return the resulting struct.

```elixir
defmodule Factory do
  @moduledoc """
  A lightweight, self-contained test-data factory with **trait composition**.

  Precedence when building a struct is:

      factory defaults  <  traits (left to right)  <  explicit overrides

  ## Usage

      Factory.build(:user)                       # defaults
      Factory.build(:user, name: "Ada")          # keyword list => overrides
      Factory.build(:user, [:admin])             # atom list    => traits
      Factory.build(:user, [:admin], role: "x")  # explicit form
      Factory.insert(:post, [:published])
  """

  @compile {:no_warn_undefined, MyApp.Repo}

  @agent __MODULE__.SequenceAgent

  # -------------------------------------------------------------------------
  # Agent lifecycle + sequences
  # -------------------------------------------------------------------------

  @doc "Starts the named Agent backing all sequence counters."
  @spec start() :: {:ok, pid()} | {:error, term()}
  def start do
    Agent.start_link(fn -> %{} end, name: @agent)
  end

  @doc "Returns the next value for the named sequence."
  @spec sequence(term(), (pos_integer() -> value)) :: value when value: var
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

  @doc "Builds a struct for `name` using factory defaults."
  @spec build(atom()) :: struct()
  def build(name), do: build(name, [], [])

  @doc """
  Builds a struct for `name`. `opts` is either a keyword list of overrides or a
  list of trait atoms; the shape is inferred.
  """
  @spec build(atom(), keyword() | [atom()]) :: struct()
  def build(name, opts) when is_list(opts) do
    {traits, overrides} = split_opts(opts)
    build(name, traits, overrides)
  end

  @doc "Builds `name` applying `traits` (atoms) then `overrides` (keyword list)."
  @spec build(atom(), [atom()], keyword()) :: struct()
  def build(name, traits, overrides) when is_list(traits) and is_list(overrides) do
    # TODO
  end

  # -------------------------------------------------------------------------
  # insert
  # -------------------------------------------------------------------------

  @doc "Builds with factory defaults and persists via `MyApp.Repo`."
  @spec insert(atom()) :: struct()
  def insert(name), do: insert(name, [], [])

  @doc "Builds from `opts` (overrides or traits) and persists."
  @spec insert(atom(), keyword() | [atom()]) :: struct()
  def insert(name, opts) when is_list(opts) do
    {traits, overrides} = split_opts(opts)
    insert(name, traits, overrides)
  end

  @doc "Builds with `traits` then `overrides`, then persists."
  @spec insert(atom(), [atom()], keyword()) :: struct()
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