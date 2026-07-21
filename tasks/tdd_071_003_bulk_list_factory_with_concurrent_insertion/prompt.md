# Make this test suite pass

Below is a complete, self-contained ExUnit test suite. Treat it as the
full specification: write the module (or modules) under test so that
every test passes. Use only what the tests themselves require — the
standard library and OTP unless the suite references anything else.
Follow idiomatic Elixir house style (`@moduledoc`, `@doc` + `@spec` on
the public API, no compiler warnings).

## The test suite

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
    params = Factory.params_for(:user, name: "Grace")
    assert params.name == "Grace"
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

Give me the complete implementation in a single file — the module(s)
alone, not the tests.
