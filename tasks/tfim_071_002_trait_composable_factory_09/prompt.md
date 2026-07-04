# Fill in the middle: implement the blanked test

Below is a module and its ExUnit test harness with the body of ONE `test` removed
(marked `# TODO`). The test's name states what it must verify. Implement just that one
test so the harness passes for a correct implementation of the module.

## Module under test

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

## Test harness — implement the `# TODO` test

```elixir
# ---------------------------------------------------------------------------
# Schema structs — stand-ins for what would be Ecto schemas in a real app.
# ---------------------------------------------------------------------------

defmodule MyApp.User do
  defstruct [:id, :name, :email, role: "member", active: true]
end

defmodule MyApp.Post do
  defstruct [:id, :title, :body, :user_id, published: false]
end

# ---------------------------------------------------------------------------
# FakeRepo — an in-memory repo standing in for MyApp.Repo in tests.
# ---------------------------------------------------------------------------

defmodule FakeRepo do
  use Agent

  def start_link(_),
    do: Agent.start_link(fn -> %{next_id: 1, records: []} end, name: __MODULE__)

  def insert!(struct) do
    Agent.get_and_update(__MODULE__, fn %{next_id: id, records: records} = state ->
      record = Map.put(struct, :id, id)
      {record, %{state | next_id: id + 1, records: [record | records]}}
    end)
  end

  def all, do: Agent.get(__MODULE__, & &1.records)
end

defmodule MyApp.Repo do
  defdelegate insert!(struct), to: FakeRepo
end

# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------

defmodule FactoryTest do
  use ExUnit.Case, async: false

  setup_all do
    FakeRepo.start_link([])
    Factory.start()
    :ok
  end

  # Defaults

  test "build/1 returns a struct with default fields" do
    user = Factory.build(:user)
    assert is_binary(user.name) and user.name != ""
    assert is_binary(user.email) and user.email != ""
    assert user.role == "member"
    assert user.active == true
  end

  test "build/1 does not touch the database" do
    before = length(FakeRepo.all())
    Factory.build(:user)
    assert length(FakeRepo.all()) == before
  end

  # Overrides via 2-arity keyword form

  test "build/2 with a keyword list applies overrides" do
    user = Factory.build(:user, name: "Ada Lovelace", email: "ada@example.com")
    assert user.name == "Ada Lovelace"
    assert user.email == "ada@example.com"
    assert user.role == "member"
  end

  # Traits via 2-arity atom-list form

  test "build/2 with a trait list applies traits" do
    user = Factory.build(:user, [:admin])
    assert user.role == "admin"
    assert user.active == true
  end

  test "multiple traits are applied left to right" do
    user = Factory.build(:user, [:admin, :inactive])
    assert user.role == "admin"
    assert user.active == false
  end

  # Explicit 3-arity form + precedence

  test "explicit overrides beat traits" do
    user = Factory.build(:user, [:admin], role: "superuser")
    assert user.role == "superuser"
  end

  test "traits beat factory defaults" do
    default = Factory.build(:user)
    assert default.role == "member"
    admin = Factory.build(:user, [:admin], [])
    assert admin.role == "admin"
  end

  test "unknown trait raises ArgumentError" do
    # TODO
  end

  # insert with traits

  test "insert/2 with a trait persists the trait values" do
    user = Factory.insert(:user, [:admin])
    assert is_integer(user.id)
    assert user.role == "admin"
  end

  test "insert/3 applies traits then overrides then persists" do
    user = Factory.insert(:user, [:admin, :inactive], name: "Root")
    assert user.name == "Root"
    assert user.role == "admin"
    assert user.active == false
    assert is_integer(user.id)
  end

  # Post trait + association

  test "post :published trait flips the published flag" do
    post = Factory.build(:post, [:published])
    assert post.published == true
    assert is_integer(post.user_id)
  end

  test "build(:post) auto-inserts a user for the association" do
    before = length(FakeRepo.all())
    post = Factory.build(:post)
    assert post.published == false
    assert is_integer(post.user_id) and post.user_id > 0
    assert length(FakeRepo.all()) == before + 1
  end

  test "user_id override skips the auto-association" do
    existing = Factory.insert(:user)
    before = length(FakeRepo.all())
    post = Factory.build(:post, user_id: existing.id)
    assert post.user_id == existing.id
    assert length(FakeRepo.all()) == before
  end

  # Sequences

  test "sequence/2 returns distinct values" do
    a = Factory.sequence(:seq_x, fn n -> "x-#{n}" end)
    b = Factory.sequence(:seq_x, fn n -> "x-#{n}" end)
    assert a == "x-1"
    assert b == "x-2"
  end

  test "default emails are unique across builds" do
    users = Enum.map(1..5, fn _ -> Factory.build(:user) end)
    emails = Enum.map(users, & &1.email)
    assert length(Enum.uniq(emails)) == 5
  end

  test "sequences are safe under concurrent access" do
    tasks =
      for _ <- 1..50 do
        Task.async(fn -> Factory.sequence(:concurrent_seq, fn n -> n end) end)
      end

    results = Task.await_many(tasks)
    assert length(Enum.uniq(results)) == 50
  end
end
```
