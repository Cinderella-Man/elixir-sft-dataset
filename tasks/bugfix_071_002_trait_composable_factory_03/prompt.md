# Fix the bug

The module below was written for the task that follows, but ONE behavior bug
slipped in. The test suite (not shown) fails with the report at the bottom.
Find the bug and fix it — change as little as possible; do not restructure
working code. Reply with the complete corrected module.

## The task the module implements

Write me an Elixir module called `Factory` that generates test data similarly to
ExMachina, but simpler and self-contained — with **trait composition** on top of
the basic build/insert API.

I need these functions in the public API:

- `Factory.build(factory_name)` — returns a struct for the named factory without
  touching the database.
- `Factory.build(factory_name, opts)` — `opts` is either a **keyword list of field
  overrides** (e.g. `name: "Ada"`) or a **list of trait atoms** (e.g. `[:admin]`).
  The module must figure out which one you meant: a proper keyword list is treated
  as overrides, a list of bare atoms as traits.
- `Factory.build(factory_name, traits, overrides)` — the explicit form: apply the
  named `traits` (a list of atoms) and then the `overrides` (a keyword list).
- `Factory.insert(factory_name)` / `insert(factory_name, opts)` /
  `insert(factory_name, traits, overrides)` — the same three shapes, but each
  persists the built struct via `MyApp.Repo.insert!` and returns the persisted
  struct.
- `Factory.sequence(name, formatter_fn)` — returns the next value for a named
  sequence by calling `formatter_fn.(n)` where `n` is a monotonically increasing
  integer starting at 1. Each call with the same `name` increments its own
  independent counter. Sequences must stay unique across the whole test run even
  under concurrent (`async: true`) access, backed by a named `Agent`.

**Traits** are named, reusable overlays of field values, declared inside the
`Factory` module (e.g. a `def trait(factory_name, trait_name)` convention returning
a keyword list). Precedence, from lowest to highest, must be:
**factory defaults → traits (applied left to right) → explicit overrides.**
Requesting an unknown trait must raise `ArgumentError`.

At minimum define factories for:

- `:user` — fields `name`, `email`, `role` (default `"member"`), `active`
  (default `true`).
- `:post` — fields `title`, `body`, `user_id`. The `:post` factory must
  automatically call `Factory.insert(:user)` to create its association and
  populate `user_id`, unless `user_id` is supplied as an override (in which case no
  user row is created).

Define at least these traits: `{:user, :admin}` (sets `role` to `"admin"`),
`{:user, :inactive}` (sets `active` to `false`), and `{:post, :published}` (sets a
`published` boolean field to `true`; `:post` defaults it to `false`).

Use only the Elixir standard library and assume `Repo` is available as
`MyApp.Repo`. Deliver everything in a single file.

## Additional interface contract

- The struct modules `MyApp.User` and `MyApp.Post` (with exactly the fields listed above) are provided by the test environment, just like `MyApp.Repo` — do NOT define `MyApp.User`, `MyApp.Post`, or `MyApp.Repo` in your file. Reference them (build with `struct/2`/`struct!/2`) and use `@compile {:no_warn_undefined, ...}` as needed so your single file compiles warning-free on its own.
- Define `Factory.start/0`: it starts the named `Agent` that backs the sequence counters and returns that `Agent.start_link/2` result. The test suite calls `Factory.start()` once (in `setup_all`) before using any other factory function.

## The buggy module

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
  defp trait(:post, :published), do: [published: false]

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

## Failing test report

```
1 of 16 test(s) failed:

  * test post :published trait flips the published flag
      
      
      Assertion with == failed
      code:  assert post.published == true
      left:  false
      right: true
```
