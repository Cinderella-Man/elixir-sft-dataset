# Fill in the middle: implement the blanked test

Below is a module and its ExUnit test harness with the body of ONE `test` removed
(marked `# TODO`). The test's name states what it must verify. Implement just that one
test so the harness passes for a correct implementation of the module.

## Module under test

```elixir
defmodule Factory do
  @moduledoc """
  A lightweight, self-contained test-data factory inspired by ExMachina.

  ## Setup

  Start the sequence Agent once in `test/test_helper.exs`:

      Factory.start()

  ## Usage

      user = Factory.build(:user)
      user = Factory.build(:user, name: "Ada Lovelace")

      user = Factory.insert(:user)
      post = Factory.insert(:post, title: "Override title")

      email = Factory.sequence(:email, &"user-\#{&1}@example.com")
      # => "user-1@example.com", "user-2@example.com", …
  """

  # MyApp.Repo is provided by the host application and is not available at
  # compile time of this file. Suppress the "undefined or private" warning.
  @compile {:no_warn_undefined, MyApp.Repo}

  @agent __MODULE__.SequenceAgent

  # -------------------------------------------------------------------------
  # Agent lifecycle
  # -------------------------------------------------------------------------

  @doc """
  Starts the named Agent that backs all sequence counters.
  Safe to call multiple times; subsequent calls are no-ops.

  The Agent is started unlinked: sequence counters must survive the caller
  (uniqueness holds for the entire test run, not one caller's lifetime).
  """
  @spec start() :: {:ok, pid()} | {:error, {:already_started, pid()}}
  def start do
    Agent.start(fn -> %{} end, name: @agent)
  end

  # -------------------------------------------------------------------------
  # Sequences
  # -------------------------------------------------------------------------

  @doc """
  Returns the next value for the sequence identified by `name`.

  `formatter_fn` receives a monotonically increasing integer (starting at 1).
  Each distinct `name` has its own independent counter. The increment is
  atomic, making sequences safe for concurrent (`async: true`) tests.

      iex> Factory.sequence(:email, &"user-\#{&1}@example.com")
      "user-1@example.com"
  """
  @spec sequence(atom() | String.t(), (pos_integer() -> any())) :: any()
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
  # Public build / insert API
  # -------------------------------------------------------------------------

  @doc "Builds a struct for `factory_name` without touching the database."
  @spec build(atom()) :: struct()
  def build(factory_name), do: build(factory_name, [])

  @doc """
  Builds a struct for `factory_name`, merging `overrides` into the result.

  Association fields stored as zero-arity thunks (`fn -> value end`) are
  resolved *after* overrides are merged. Overriding `user_id:` on a `:post`
  therefore suppresses the implicit `insert(:user)` call entirely.
  """
  @spec build(atom(), Keyword.t()) :: struct()
  def build(factory_name, overrides) do
    factory_name
    |> factory()
    |> merge_overrides(overrides)
    |> resolve_thunks()
  end

  @doc "Builds and persists a struct for `factory_name` via `MyApp.Repo`."
  @spec insert(atom()) :: struct()
  def insert(factory_name), do: insert(factory_name, [])

  @doc "Builds with `overrides`, then persists via `MyApp.Repo`."
  @spec insert(atom(), Keyword.t()) :: struct()
  def insert(factory_name, overrides) do
    factory_name
    |> build(overrides)
    |> MyApp.Repo.insert!()
  end

  # -------------------------------------------------------------------------
  # Internal helpers
  # -------------------------------------------------------------------------

  @spec merge_overrides(struct(), Keyword.t()) :: struct()
  defp merge_overrides(base, []), do: base
  defp merge_overrides(base, overrides), do: struct(base, overrides)

  # Walk every field; call any zero-arity function (thunk) to produce its
  # value. Thunks are only evaluated for fields that were NOT overridden,
  # since merge_overrides replaces function values before this step runs.
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

  # Allows the factory to be used without an explicit Factory.start/0 call
  # in simple scripts, at the cost of losing supervised lifecycle management.
  # Started UNLINKED: sequences must stay unique across the entire test run,
  # so the counter process cannot be linked to (and torn down with) whichever
  # caller happened to touch it first. Two racing callers can both attempt the
  # start; the loser's :already_started is success.
  defp ensure_agent_started do
    case Process.whereis(@agent) do
      nil ->
        case Agent.start(fn -> %{} end, name: @agent) do
          {:ok, _pid} -> :ok
          {:error, {:already_started, _pid}} -> :ok
        end

      _pid ->
        :ok
    end
  end

  # -------------------------------------------------------------------------
  # Factory definitions
  # -------------------------------------------------------------------------
  # Each clause of `factory/1` returns a struct populated with default values.
  #
  # Wrap association fields that need a DB insert in a zero-arity thunk.
  # resolve_thunks/1 calls them only when the field has NOT been overridden,
  # so `Factory.insert(:post, user_id: id)` never creates a spurious user row.
  # -------------------------------------------------------------------------

  @spec factory(atom()) :: struct()

  defp factory(:user) do
    # struct!/2 is a runtime call — no compile-time dependency on MyApp.User.
    struct!(MyApp.User,
      name: sequence(:user_name, &"User #{&1}"),
      email: sequence(:user_email, &"user-#{&1}@example.com")
    )
  end

  defp factory(:post) do
    # user_id is a thunk: resolved after overrides, so passing
    # `user_id: existing_id` skips the insert(:user) call entirely.
    struct!(MyApp.Post,
      title: sequence(:post_title, &"Post title #{&1}"),
      body: sequence(:post_body, &"Post body #{&1}. Lorem ipsum dolor sit amet."),
      user_id: fn -> insert(:user).id end
    )
  end

  defp factory(name) do
    raise ArgumentError, """
    No factory defined for #{inspect(name)}.
    Add a `defp factory(#{inspect(name)})` clause to #{__MODULE__}.
    """
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
# FakeRepo — an in-memory repo that satisfies the MyApp.Repo.insert!/1
# contract without touching a real database.
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

# ---------------------------------------------------------------------------
# MyApp.Repo — the module Factory calls. Delegates to FakeRepo in tests;
# in a real app this would be your Ecto.Repo.
# ---------------------------------------------------------------------------

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

  # build/1 — no DB side effects

  test "build/1 returns a struct with default fields" do
    user = Factory.build(:user)
    assert %{name: name, email: email} = user
    assert is_binary(name) and name != ""
    assert is_binary(email) and email != ""
  end

  test "build/1 does not insert into the database" do
    # TODO
  end

  # build/2 — overrides

  test "build/2 merges overrides into the struct" do
    user = Factory.build(:user, name: "Ada Lovelace", email: "ada@example.com")
    assert user.name == "Ada Lovelace"
    assert user.email == "ada@example.com"
  end

  test "build/2 only overrides specified fields, leaves others as defaults" do
    user = Factory.build(:user, name: "Grace Hopper")
    assert user.name == "Grace Hopper"
    assert is_binary(user.email) and user.email != ""
  end

  # insert/1 and insert/2

  test "insert/1 returns a struct with an id" do
    user = Factory.insert(:user)
    assert is_integer(user.id) and user.id > 0
  end

  test "insert/2 persists the override values" do
    user = Factory.insert(:user, name: "Linus Torvalds")
    assert user.name == "Linus Torvalds"
    assert is_integer(user.id)
  end

  test "insert/1 actually adds a record to the repo" do
    before_count = length(FakeRepo.all())
    Factory.insert(:user)
    assert length(FakeRepo.all()) == before_count + 1
  end

  # sequence/2 — uniqueness

  test "sequence/2 returns distinct values on consecutive calls" do
    e1 = Factory.sequence(:email_seq_test, fn n -> "user#{n}@test.com" end)
    e2 = Factory.sequence(:email_seq_test, fn n -> "user#{n}@test.com" end)
    e3 = Factory.sequence(:email_seq_test, fn n -> "user#{n}@test.com" end)

    assert e1 != e2
    assert e2 != e3
    assert e1 != e3
  end

  test "different sequence names are independent counters" do
    a1 = Factory.sequence(:seq_a, fn n -> "a-#{n}" end)
    b1 = Factory.sequence(:seq_b, fn n -> "b-#{n}" end)
    a2 = Factory.sequence(:seq_a, fn n -> "a-#{n}" end)
    b2 = Factory.sequence(:seq_b, fn n -> "b-#{n}" end)

    assert a1 == "a-1"
    assert b1 == "b-1"
    assert a2 == "a-2"
    assert b2 == "b-2"
  end

  test "email fields generated by default use sequences and are unique" do
    users = for _ <- 1..5, do: Factory.build(:user)
    emails = Enum.map(users, & &1.email)
    assert length(Enum.uniq(emails)) == 5
  end

  # Associations — :post auto-creates a :user

  test "build(:post) populates user_id via an inserted user" do
    before_count = length(FakeRepo.all())
    post = Factory.build(:post)

    assert is_integer(post.user_id) and post.user_id > 0
    assert length(FakeRepo.all()) == before_count + 1
  end

  test "insert(:post) inserts both the post and its user" do
    before_count = length(FakeRepo.all())
    post = Factory.insert(:post)

    assert is_integer(post.id)
    assert is_integer(post.user_id)
    assert length(FakeRepo.all()) >= before_count + 2
  end

  test "insert(:post, user_id: id) respects user_id override and skips auto-association" do
    existing_user = Factory.insert(:user)
    before_count = length(FakeRepo.all())

    post = Factory.insert(:post, user_id: existing_user.id)
    assert post.user_id == existing_user.id
    assert length(FakeRepo.all()) == before_count + 1
  end

  # Concurrent safety

  test "sequences are safe under concurrent access" do
    tasks =
      for _ <- 1..50 do
        Task.async(fn ->
          Factory.sequence(:concurrent_seq, fn n -> n end)
        end)
      end

    results = Task.await_many(tasks)
    assert length(Enum.uniq(results)) == 50
  end
end
```
