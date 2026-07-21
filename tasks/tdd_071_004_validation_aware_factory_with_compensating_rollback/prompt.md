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
# FakeRepo — an in-memory repo supporting insert! and delete!.
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

  def delete!(%{id: id} = struct) do
    Agent.update(__MODULE__, fn %{records: records} = state ->
      %{state | records: Enum.reject(records, &(&1.id == id))}
    end)

    struct
  end

  def all, do: Agent.get(__MODULE__, & &1.records)
end

defmodule MyApp.Repo do
  defdelegate insert!(struct), to: FakeRepo
  defdelegate delete!(struct), to: FakeRepo
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

  # build

  test "build/1 returns a struct with default fields" do
    user = Factory.build(:user)
    assert is_binary(user.name) and user.name != ""
    assert is_binary(user.email) and user.email != ""
  end

  test "build(:post) creates the association record and assigns its id" do
    before = length(FakeRepo.all())
    post = Factory.build(:post)

    # The auto-created user is persisted so that its id can be assigned.
    assert is_integer(post.user_id)
    assert length(FakeRepo.all()) == before + 1

    assert Enum.any?(FakeRepo.all(), fn
             %MyApp.User{id: id} -> id == post.user_id
             _ -> false
           end)
  end

  test "build(:post) with a user_id override creates no association record" do
    {:ok, existing} = Factory.insert(:user)
    before = length(FakeRepo.all())

    post = Factory.build(:post, user_id: existing.id)

    assert post.user_id == existing.id
    assert length(FakeRepo.all()) == before
  end

  # insert success semantics

  test "insert/1 returns {:ok, struct} with an id on success" do
    assert {:ok, user} = Factory.insert(:user)
    assert is_integer(user.id)
  end

  test "insert/2 persists override values on success" do
    assert {:ok, user} = Factory.insert(:user, name: "Linus")
    assert user.name == "Linus"
  end

  test "insert/1 actually adds a record on success" do
    before = length(FakeRepo.all())
    assert {:ok, _} = Factory.insert(:user)
    assert length(FakeRepo.all()) == before + 1
  end

  # insert failure semantics

  test "insert with a nil required field returns a missing_fields error" do
    assert {:error, {:missing_fields, fields}} = Factory.insert(:user, name: nil)
    assert :name in fields
  end

  test "failed insert does not add any record" do
    before = length(FakeRepo.all())
    assert {:error, _} = Factory.insert(:user, email: nil)
    assert length(FakeRepo.all()) == before
  end

  test "reports every missing required field" do
    assert {:error, {:missing_fields, fields}} =
             Factory.insert(:user, name: nil, email: nil)

    assert :name in fields
    assert :email in fields
  end

  # Compensating rollback of associations

  test "insert(:post) success inserts both user and post" do
    before = length(FakeRepo.all())
    assert {:ok, post} = Factory.insert(:post)
    assert is_integer(post.id)
    assert is_integer(post.user_id)
    assert length(FakeRepo.all()) == before + 2
  end

  test "failed insert(:post) rolls back the auto-created user" do
    before = length(FakeRepo.all())
    assert {:error, {:missing_fields, fields}} = Factory.insert(:post, title: nil)
    assert :title in fields
    # The user auto-created for the association must be deleted again.
    assert length(FakeRepo.all()) == before
  end

  test "user_id override on a failing post leaves no stray rows" do
    {:ok, existing} = Factory.insert(:user)
    before = length(FakeRepo.all())
    assert {:error, _} = Factory.insert(:post, user_id: existing.id, body: nil)
    assert length(FakeRepo.all()) == before
  end

  # insert!

  test "insert!/1 returns the struct on success" do
    user = Factory.insert!(:user)
    assert is_integer(user.id)
  end

  test "insert!/2 raises on validation failure" do
    assert_raise ArgumentError, fn -> Factory.insert!(:user, name: nil) end
  end

  # valid?

  test "valid? is true for a complete struct and false for a missing field" do
    assert Factory.valid?(:user)
    refute Factory.valid?(:user, email: nil)
  end

  test "valid? on a post does not leave stray association rows" do
    before = length(FakeRepo.all())
    assert Factory.valid?(:post)
    assert length(FakeRepo.all()) == before
  end

  # Sequences

  test "sequence/2 returns distinct values" do
    a = Factory.sequence(:s3, fn n -> n end)
    b = Factory.sequence(:s3, fn n -> n end)
    assert a != b
  end

  test "sequence/2 counts up from 1 by one on each call" do
    assert Factory.sequence(:counting_seq, fn n -> n end) == 1
    assert Factory.sequence(:counting_seq, fn n -> n end) == 2
    assert Factory.sequence(:counting_seq, fn n -> n end) == 3
  end

  test "each sequence name has an independent counter starting at 1" do
    assert Factory.sequence(:independent_seq_a, fn n -> n end) == 1
    assert Factory.sequence(:independent_seq_b, fn n -> n end) == 1
    assert Factory.sequence(:independent_seq_a, fn n -> n end) == 2
    assert Factory.sequence(:independent_seq_b, fn n -> n end) == 2
  end

  test "sequences are safe under concurrent access" do
    tasks =
      for _ <- 1..50 do
        Task.async(fn -> Factory.sequence(:concurrent_seq, fn n -> n end) end)
      end

    results = Task.await_many(tasks)
    assert length(Enum.uniq(results)) == 50
  end

  test "concurrent access yields exactly the integers 1..50 for one sequence" do
    tasks =
      for _ <- 1..50 do
        Task.async(fn -> Factory.sequence(:concurrent_range_seq, fn n -> n end) end)
      end

    results = Task.await_many(tasks)
    assert Enum.sort(results) == Enum.to_list(1..50)
  end

  test "insert!(:post) raising on validation failure still rolls back the auto-created user" do
    before = length(FakeRepo.all())
    assert_raise ArgumentError, fn -> Factory.insert!(:post, body: nil) end
    assert length(FakeRepo.all()) == before
  end

  test "sequence/2 formats each counter value through formatter_fn" do
    assert Factory.sequence(:formatted_seq, &"item-#{&1}") == "item-1"
    assert Factory.sequence(:formatted_seq, &"item-#{&1}") == "item-2"
  end

  test "valid?(:post, title: nil) is false and rolls back its association row" do
    before = length(FakeRepo.all())
    refute Factory.valid?(:post, title: nil)
    assert length(FakeRepo.all()) == before
  end

  test "build/2 merges plain field overrides without persisting anything" do
    before = length(FakeRepo.all())
    user = Factory.build(:user, name: "Ada", email: "ada@example.com")
    assert %MyApp.User{name: "Ada", email: "ada@example.com"} = user
    assert length(FakeRepo.all()) == before
  end

  test "insert(:post) with a user_id override inserts only the post record" do
    {:ok, existing} = Factory.insert(:user)
    before = length(FakeRepo.all())
    assert {:ok, post} = Factory.insert(:post, user_id: existing.id)
    assert post.user_id == existing.id
    assert length(FakeRepo.all()) == before + 1
  end

  test "start/0 returns the raw Agent.start_link/2 result when already started" do
    assert {:error, {:already_started, pid}} = Factory.start()
    assert is_pid(pid)
  end

  test "build(:post) leaves every required field populated, none unresolved" do
    post = Factory.build(:post)
    assert %MyApp.Post{} = post
    assert is_binary(post.title) and post.title != ""
    assert is_binary(post.body) and post.body != ""
    assert is_integer(post.user_id)
  end

  test "each build(:post) creates its own user row with a distinct id" do
    before = length(FakeRepo.all())
    post_a = Factory.build(:post)
    post_b = Factory.build(:post)

    assert is_integer(post_a.user_id)
    assert is_integer(post_b.user_id)
    assert post_a.user_id != post_b.user_id
    assert length(FakeRepo.all()) == before + 2

    for id <- [post_a.user_id, post_b.user_id] do
      assert Enum.any?(FakeRepo.all(), fn
               %MyApp.User{id: row_id} -> row_id == id
               _ -> false
             end)
    end
  end

  test "a fresh sequence yields the dense run 1..10 with no gaps or repeats" do
    values = for _ <- 1..10, do: Factory.sequence(:dense_seq, fn n -> n end)
    assert values == Enum.to_list(1..10)
  end

  test "a sequence counter is unaffected by other names and by factory traffic" do
    assert Factory.sequence(:isolated_seq, fn n -> n end) == 1

    for name <- [:noise_seq_a, :noise_seq_b], _ <- 1..5 do
      Factory.sequence(name, fn n -> n end)
    end

    Factory.build(:user)

    assert Factory.sequence(:isolated_seq, fn n -> n end) == 2
  end

  test "concurrent access keeps two sequence names on separate counters" do
    tasks =
      for name <- [:par_seq_a, :par_seq_b], _ <- 1..25 do
        Task.async(fn -> {name, Factory.sequence(name, fn n -> n end)} end)
      end

    grouped =
      tasks
      |> Task.await_many()
      |> Enum.group_by(fn {name, _} -> name end, fn {_, n} -> n end)

    assert Enum.sort(grouped[:par_seq_a]) == Enum.to_list(1..25)
    assert Enum.sort(grouped[:par_seq_b]) == Enum.to_list(1..25)
  end
end
```

Give me the complete implementation in a single file — the module(s)
alone, not the tests.
