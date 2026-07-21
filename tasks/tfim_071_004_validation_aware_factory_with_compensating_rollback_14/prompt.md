# Fill in the middle: implement the blanked test

Below is a module and its ExUnit test harness with the body of ONE `test` removed
(marked `# TODO`). The test's name states what it must verify. Implement just that one
test so the harness passes for a correct implementation of the module.

## Module under test

```elixir
defmodule Factory do
  @moduledoc """
  A lightweight, self-contained test-data factory with **validation and
  compensating rollback**.

  `insert/2` validates required fields; on failure it returns an error tuple and
  deletes any association records auto-created while building the invalid parent,
  leaving the repo unchanged.

  ## Usage

      {:ok, user}   = Factory.insert(:user)
      {:error, err} = Factory.insert(:user, name: nil)
      user          = Factory.insert!(:user)     # raises on failure
      Factory.valid?(:post)                       # => true
  """

  @compile {:no_warn_undefined, MyApp.Repo}

  @agent __MODULE__.SequenceAgent

  @typedoc "The name of a declared factory."
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
  @spec sequence(atom(), (pos_integer() -> value)) :: value when value: term()
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

  @doc "Builds a struct for `name` (resolving/creating any associations)."
  @spec build(factory_name()) :: struct()
  def build(name), do: build(name, [])

  @doc "Builds a struct for `name`, merging `overrides`."
  @spec build(factory_name(), overrides()) :: struct()
  def build(name, overrides) do
    {struct, _assocs} = build_with_assocs(name, overrides)
    struct
  end

  # -------------------------------------------------------------------------
  # insert / insert! with validation + compensation
  # -------------------------------------------------------------------------

  @doc "Builds, validates and inserts `name`; see `insert/2`."
  @spec insert(factory_name()) ::
          {:ok, struct()} | {:error, {:missing_fields, [atom()]}}
  def insert(name), do: insert(name, [])

  @doc """
  Builds and validates `name`; on success persists and returns `{:ok, struct}`,
  otherwise rolls back auto-created associations and returns
  `{:error, {:missing_fields, fields}}`.
  """
  @spec insert(factory_name(), overrides()) ::
          {:ok, struct()} | {:error, {:missing_fields, [atom()]}}
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

  @doc "Like `insert/2` but returns the struct on success and raises otherwise."
  @spec insert!(factory_name()) :: struct()
  def insert!(name), do: insert!(name, [])

  @doc "Like `insert/2` but returns the struct on success and raises otherwise."
  @spec insert!(factory_name(), overrides()) :: struct()
  def insert!(name, overrides) do
    case insert(name, overrides) do
      {:ok, struct} ->
        struct

      {:error, reason} ->
        raise ArgumentError,
              "insert!/2 failed for #{inspect(name)}: #{inspect(reason)}"
    end
  end

  @doc """
  Returns whether a built `name` (with `overrides`) is valid. Any association
  rows created during the check are rolled back so no stray rows remain.
  """
  @spec valid?(factory_name()) :: boolean()
  @spec valid?(factory_name(), overrides()) :: boolean()
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
    # TODO
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
