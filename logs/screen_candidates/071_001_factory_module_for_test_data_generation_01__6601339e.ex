defmodule Factory.User do
  @moduledoc false
  defstruct [:id, :name, :email]
end

defmodule Factory.Post do
  @moduledoc false
  defstruct [:id, :title, :body, :user_id]
end

defmodule Factory do
  @moduledoc """
  A tiny, self-contained test-data factory in the spirit of ExMachina.

  It supports building in-memory structs, inserting them through an Ecto
  repository (`MyApp.Repo`), and producing globally-unique sequence values
  that stay unique even when tests run with `async: true`.

  Factories are declared with the `def factory(:name)` convention. Two
  factories ship by default:

    * `:user` with `name` and `email`
    * `:post` with `title`, `body` and `user_id`

  The `:post` factory eagerly inserts a `:user` (via `insert/1`) to obtain a
  real database id for its `user_id` association, unless an explicit
  `user_id` override is supplied — in which case no extra user is created.

  Associations that are plain embedded structs (none ship by default) would
  be built eagerly during `build/1`; associations that need a database id are
  only materialised during `insert/1,2`.
  """

  alias Factory.{Post, User}

  @repo MyApp.Repo
  @agent Factory.SequenceAgent

  @doc """
  Starts the named sequence `Agent`.

  Safe to call multiple times and from multiple processes; a second start is
  treated as success. Called automatically on first use, so explicit
  invocation is optional.
  """
  @spec start() :: :ok
  def start, do: ensure_agent()

  @doc """
  Builds a struct for `factory_name` without touching the database.
  """
  @spec build(atom()) :: struct()
  @spec build(atom(), keyword()) :: struct()
  def build(factory_name, overrides \\ []) do
    factory_name
    |> factory()
    |> struct(overrides)
  end

  @doc """
  Builds a struct for `factory_name`, resolves any database-backed
  associations, inserts it via `MyApp.Repo.insert!/1` and returns the
  persisted struct.
  """
  @spec insert(atom()) :: struct()
  @spec insert(atom(), keyword()) :: struct()
  def insert(factory_name, overrides \\ []) do
    factory_name
    |> build(overrides)
    |> resolve_associations(factory_name)
    |> persist()
  end

  @doc """
  Returns the next value for the named sequence `name`.

  Calls `formatter_fn.(n)` where `n` is a monotonically increasing integer
  starting at `1`. Each `name` keeps its own independent counter, and the
  underlying counter lives in a single named `Agent`, so values are unique
  across the whole test run even under concurrency.
  """
  @spec sequence(atom(), (pos_integer() -> term())) :: term()
  def sequence(name, formatter_fn) when is_function(formatter_fn, 1) do
    ensure_agent()

    n =
      Agent.get_and_update(@agent, fn state ->
        next = Map.get(state, name, 0) + 1
        {next, Map.put(state, name, next)}
      end)

    formatter_fn.(n)
  end

  @doc """
  Returns a fresh struct for the given factory `name`.

  This is the extension point for declaring new factories: add another
  `factory/1` clause that returns the desired struct.
  """
  @spec factory(atom()) :: struct()
  def factory(:user) do
    %User{
      name: sequence(:user_name, &"User #{&1}"),
      email: sequence(:user_email, &"user#{&1}@example.com")
    }
  end

  def factory(:post) do
    %Post{
      title: sequence(:post_title, &"Post Title #{&1}"),
      body: "post body",
      user_id: nil
    }
  end

  # Resolve associations that require a real database id at insert time.
  # A `:post` with no `user_id` triggers a `:user` insert; an explicit
  # `user_id` override leaves it untouched, so no extra user is created.
  @spec resolve_associations(struct(), atom()) :: struct()
  defp resolve_associations(%Post{user_id: nil} = post, :post) do
    user = insert(:user)
    %{post | user_id: user.id}
  end

  defp resolve_associations(struct, _factory_name), do: struct

  @spec persist(struct()) :: struct()
  defp persist(struct), do: apply(@repo, :insert!, [struct])

  @spec ensure_agent() :: :ok
  defp ensure_agent do
    case Agent.start(fn -> %{} end, name: @agent) do
      {:ok, _pid} -> :ok
      {:error, {:already_started, _pid}} -> :ok
    end
  end
end