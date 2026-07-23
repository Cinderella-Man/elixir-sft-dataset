# One test is missing its body

Module plus harness below; a single `test` body was replaced with
`# TODO`. Reconstruct it from its name and the surrounding suite so the
harness passes for a correct implementation of the module. Touch nothing
else.

## Module under test

```elixir
defmodule Factory do
  @moduledoc """
  A lightweight, self-contained test-data factory with **bulk generation**.

  Adds `build_list/2,3`, `insert_list/2,3` (concurrent), and `params_for/1,2`
  on top of the usual `build`, `insert`, and `sequence` API.

  ## Usage

      Factory.build_list(3, :user)
      Factory.insert_list(100, :user)          # concurrent inserts
      Factory.params_for(:user, name: "Ada")   # plain map, no :id
  """

  @compile {:no_warn_undefined, MyApp.Repo}

  @agent __MODULE__.SequenceAgent

  @typedoc "The name identifying a factory definition."
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
  @spec sequence(term(), (pos_integer() -> value)) :: value when value: term()
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
  # Singular build / insert
  # -------------------------------------------------------------------------

  @doc "Builds a struct for `name` without touching the database."
  @spec build(factory_name()) :: struct()
  def build(name), do: build(name, [])

  @doc "Builds a struct for `name`, merging `overrides`."
  @spec build(factory_name(), overrides()) :: struct()
  def build(name, overrides) do
    name
    |> factory()
    |> merge_overrides(overrides)
    |> resolve_thunks()
  end

  @doc "Builds and persists a struct for `name`."
  @spec insert(factory_name()) :: struct()
  def insert(name), do: insert(name, [])

  @doc "Builds with `overrides`, then persists via `MyApp.Repo`."
  @spec insert(factory_name(), overrides()) :: struct()
  def insert(name, overrides) do
    name
    |> build(overrides)
    |> MyApp.Repo.insert!()
  end

  # -------------------------------------------------------------------------
  # Bulk build / insert
  # -------------------------------------------------------------------------

  @doc "Builds a list of `count` structs for `name`."
  @spec build_list(non_neg_integer(), factory_name()) :: [struct()]
  def build_list(count, name), do: build_list(count, name, [])

  @doc "Builds a list of `count` structs for `name`, each with `overrides`."
  @spec build_list(non_neg_integer(), factory_name(), overrides()) :: [struct()]
  def build_list(count, name, overrides) when is_integer(count) and count >= 0 do
    Enum.map(1..count//1, fn _ -> build(name, overrides) end)
  end

  @doc "Persists `count` structs for `name` concurrently."
  @spec insert_list(non_neg_integer(), factory_name()) :: [struct()]
  def insert_list(count, name), do: insert_list(count, name, [])

  @doc "Persists `count` structs for `name` concurrently, each with `overrides`."
  @spec insert_list(non_neg_integer(), factory_name(), overrides()) :: [struct()]
  def insert_list(count, name, overrides) when is_integer(count) and count >= 0 do
    1..count//1
    |> Enum.map(fn _ -> Task.async(fn -> insert(name, overrides) end) end)
    |> Task.await_many()
  end

  # -------------------------------------------------------------------------
  # params_for
  # -------------------------------------------------------------------------

  @doc "Returns a plain map of `name`'s fields (no struct, no `:id`)."
  @spec params_for(factory_name()) :: map()
  def params_for(name), do: params_for(name, [])

  @doc "Returns a plain map of `name`'s fields with `overrides`, minus `:id`."
  @spec params_for(factory_name(), overrides()) :: map()
  def params_for(name, overrides) do
    name
    |> build(overrides)
    |> Map.from_struct()
    |> Map.delete(:id)
  end

  # -------------------------------------------------------------------------
  # Internal helpers
  # -------------------------------------------------------------------------

  @spec merge_overrides(struct(), overrides()) :: struct()
  defp merge_overrides(base, []), do: base
  defp merge_overrides(base, overrides), do: struct(base, overrides)

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

  @spec ensure_agent_started() :: :ok
  defp ensure_agent_started do
    case Process.whereis(@agent) do
      nil ->
        Agent.start_link(fn -> %{} end, name: @agent)
        :ok

      _pid ->
        :ok
    end
  end

  # -------------------------------------------------------------------------
  # Factory definitions
  # -------------------------------------------------------------------------

  @spec factory(factory_name()) :: struct()
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
      user_id: fn -> insert(:user).id end
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
  defstruct [:id, :name, :email]
end

defmodule MyApp.Post do
  defstruct [:id, :title, :body, :user_id]
end

# ---------------------------------------------------------------------------
# FakeRepo — a concurrency-safe in-memory repo standing in for MyApp.Repo.
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

  # Singular build/insert still work

  test "build/1 returns a struct without touching the DB" do
    before = length(FakeRepo.all())
    user = Factory.build(:user)
    assert is_binary(user.email) and user.email != ""
    assert length(FakeRepo.all()) == before
  end

  test "insert/2 persists with overrides" do
    user = Factory.insert(:user, name: "Ada")
    assert user.name == "Ada"
    assert is_integer(user.id)
  end

  # build_list

  test "build_list/2 returns the requested count" do
    users = Factory.build_list(4, :user)
    assert length(users) == 4
  end

  test "build_list elements have unique sequence-driven emails" do
    users = Factory.build_list(6, :user)
    emails = Enum.map(users, & &1.email)
    assert length(Enum.uniq(emails)) == 6
  end

  test "build_list/3 applies overrides to every element" do
    users = Factory.build_list(3, :user, name: "Same")
    assert Enum.all?(users, &(&1.name == "Same"))
  end

  test "build_list of 0 returns an empty list" do
    assert Factory.build_list(0, :user) == []
  end

  test "build_list does not persist anything by itself" do
    before = length(FakeRepo.all())
    Factory.build_list(5, :user)
    assert length(FakeRepo.all()) == before
  end

  # insert_list (concurrent)

  test "insert_list/2 persists the requested count" do
    before = length(FakeRepo.all())
    users = Factory.insert_list(10, :user)
    assert length(users) == 10
    assert Enum.all?(users, &is_integer(&1.id))
    assert length(FakeRepo.all()) == before + 10
  end

  test "insert_list assigns unique ids under concurrency" do
    users = Factory.insert_list(50, :user)
    ids = Enum.map(users, & &1.id)
    assert length(Enum.uniq(ids)) == 50
  end

  test "insert_list keeps sequence-driven emails unique under concurrency" do
    users = Factory.insert_list(50, :user)
    emails = Enum.map(users, & &1.email)
    assert length(Enum.uniq(emails)) == 50
  end

  test "insert_list of 0 returns an empty list" do
    before = length(FakeRepo.all())
    assert Factory.insert_list(0, :user) == []
    assert length(FakeRepo.all()) == before
  end

  # params_for

  test "params_for returns a plain map without :id" do
    params = Factory.params_for(:user)
    assert is_map(params)
    refute is_struct(params)
    refute Map.has_key?(params, :id)
    assert is_binary(params.email)
  end

  test "params_for applies overrides" do
    # TODO
  end

  test "params_for(:post) resolves the association to an integer user_id" do
    params = Factory.params_for(:post)
    assert is_integer(params.user_id)
    refute Map.has_key?(params, :id)
  end

  # Associations

  test "insert(:post) inserts both post and user" do
    before = length(FakeRepo.all())
    post = Factory.insert(:post)
    assert is_integer(post.id)
    assert is_integer(post.user_id)
    assert length(FakeRepo.all()) >= before + 2
  end

  test "build(:post) with a user_id override keeps the id and skips the user insert" do
    before = length(FakeRepo.all())
    post = Factory.build(:post, user_id: 4242)
    assert post.user_id == 4242
    assert length(FakeRepo.all()) == before
  end

  test "insert(:post) with a user_id override persists only the post" do
    before = length(FakeRepo.all())
    post = Factory.insert(:post, user_id: 7777)
    assert post.user_id == 7777
    assert is_integer(post.id)
    assert length(FakeRepo.all()) == before + 1
  end

  # Sequences

  test "sequence/2 returns distinct consecutive values" do
    a = Factory.sequence(:s2, fn n -> n end)
    b = Factory.sequence(:s2, fn n -> n end)
    assert a != b
  end

  test "sequences are safe under concurrent access" do
    tasks =
      for _ <- 1..50 do
        Task.async(fn -> Factory.sequence(:concurrent_seq, fn n -> n end) end)
      end

    results = Task.await_many(tasks)
    assert length(Enum.uniq(results)) == 50
  end

  test "sequence/2 counters are independent per name" do
    assert Factory.sequence(:audit_indep_a, fn n -> n end) == 1
    assert Factory.sequence(:audit_indep_a, fn n -> n end) == 2
    assert Factory.sequence(:audit_indep_b, fn n -> n end) == 1
    assert Factory.sequence(:audit_indep_a, fn n -> n end) == 3
    assert Factory.sequence(:audit_indep_b, fn n -> n end) == 2
  end

  test "params_for(:post) user_id matches a user actually persisted in the repo" do
    params = Factory.params_for(:post)
    user = Enum.find(FakeRepo.all(), &(&1.id == params.user_id))
    assert %MyApp.User{} = user
    assert is_binary(user.email)
  end
end
```
