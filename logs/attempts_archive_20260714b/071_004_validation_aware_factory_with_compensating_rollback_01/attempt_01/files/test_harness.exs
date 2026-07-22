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

  test "sequences are safe under concurrent access" do
    tasks =
      for _ <- 1..50 do
        Task.async(fn -> Factory.sequence(:concurrent_seq, fn n -> n end) end)
      end

    results = Task.await_many(tasks)
    assert length(Enum.uniq(results)) == 50
  end
end