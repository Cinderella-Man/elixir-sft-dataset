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
    assert_raise ArgumentError, fn -> Factory.build(:user, [:wizard], []) end
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

  test "insert/1 persists a post row plus its association row" do
    before = length(FakeRepo.all())
    post = Factory.insert(:post)
    assert is_integer(post.id)
    records = FakeRepo.all()
    assert length(records) == before + 2

    assert Enum.any?(records, fn r ->
             match?(%MyApp.Post{}, r) and r.id == post.id
           end)
  end

  test "build(:post) populates user_id with the id of the user actually inserted" do
    post = Factory.build(:post)
    [newest | _] = FakeRepo.all()
    assert match?(%MyApp.User{}, newest)
    assert is_integer(newest.id)
    assert post.user_id == newest.id
  end

  test "distinct sequence names keep independent counters" do
    a1 = Factory.sequence(:seq_indep_a, fn n -> n end)
    a2 = Factory.sequence(:seq_indep_a, fn n -> n end)
    b1 = Factory.sequence(:seq_indep_b, fn n -> n end)
    a3 = Factory.sequence(:seq_indep_a, fn n -> n end)
    b2 = Factory.sequence(:seq_indep_b, fn n -> n end)
    assert [a1, a2, a3] == [1, 2, 3]
    assert [b1, b2] == [1, 2]
  end

  test "insert(:post) with a user_id override creates only the post row" do
    existing = Factory.insert(:user)
    before = length(FakeRepo.all())
    post = Factory.insert(:post, [:published], user_id: existing.id)
    assert post.user_id == existing.id
    assert post.published == true
    assert length(FakeRepo.all()) == before + 1
  end

  test "an explicit false override beats a trait that sets the flag true" do
    post = Factory.build(:post, [:published], published: false, user_id: 42)
    assert post.published == false
    assert post.user_id == 42
  end

  test "unknown trait raises through the inferred two-arity trait form" do
    assert_raise ArgumentError, fn -> Factory.build(:post, [:featured]) end
    assert_raise ArgumentError, fn -> Factory.insert(:user, [:wizard]) end
  end
end
