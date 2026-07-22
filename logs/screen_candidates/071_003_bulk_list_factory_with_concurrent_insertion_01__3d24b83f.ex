defmodule Factory do
  @moduledoc """
  A small, self-contained test-data factory in the spirit of `ExMachina`.

  It supports building structs, persisting them through `MyApp.Repo`, bulk
  (list) generation, params extraction and globally unique sequences.

  ## Usage

      setup_all do
        Factory.start()
        :ok
      end

      user = Factory.build(:user, name: "Ada")
      post = Factory.insert(:post)
      users = Factory.insert_list(3, :user)
      params = Factory.params_for(:user)

  ## Sequences

  `sequence/2` is backed by a named `Agent` (see `start/0`), so counters are
  shared across processes and stay unique even when test cases run with
  `async: true`.
  """

  @compile {:no_warn_undefined, MyApp.Repo}
  @compile {:no_warn_undefined, MyApp.User}
  @compile {:no_warn_undefined, MyApp.Post}

  @agent __MODULE__.Sequences

  @typedoc "The name of a factory, e.g. `:user` or `:post`."
  @type factory_name :: atom()

  @typedoc "A keyword list of field overrides applied to a built struct."
  @type overrides :: keyword()

  @doc """
  Starts the named `Agent` that backs the sequence counters.

  Returns the raw `Agent.start_link/2` result, so `{:error, {:already_started,
  pid}}` is returned when the agent is already running. Call this once, e.g.
  from a `setup_all` block, before using any other factory function.
  """
  @spec start() :: {:ok, pid()} | {:error, term()}
  def start do
    Agent.start_link(fn -> %{} end, name: @agent)
  end

  @doc """
  Returns the next value of the named sequence.

  `formatter_fn` is called with a monotonically increasing integer starting at
  `1`. Every `name` keeps its own independent counter and the increment happens
  inside the agent, so values are unique across concurrent access.

      iex> Factory.sequence(:username, &"user#\{&1}")
      "user1"
  """
  @spec sequence(term(), (pos_integer() -> value)) :: value when value: term()
  def sequence(name, formatter_fn) when is_function(formatter_fn, 1) do
    n =
      Agent.get_and_update(@agent, fn counters ->
        next = Map.get(counters, name, 0) + 1
        {next, Map.put(counters, name, next)}
      end)

    formatter_fn.(n)
  end

  @doc """
  Builds a struct for `factory_name` without touching the database.

  `overrides` is a keyword list of fields that replace the factory defaults.
  Overrides are applied after the defaults are generated, except for
  association shortcuts such as `:user_id` on the `:post` factory, which
  suppress the associated `insert/1` call entirely.
  """
  @spec build(factory_name(), overrides()) :: struct()
  def build(factory_name, overrides \\ []) do
    factory_name
    |> defaults(overrides)
    |> struct!(overrides)
  end

  @doc """
  Builds a struct for `factory_name` and persists it via `MyApp.Repo.insert!/1`.

  Returns the persisted struct, including any id assigned by the repository.
  """
  @spec insert(factory_name(), overrides()) :: struct()
  def insert(factory_name, overrides \\ []) do
    factory_name
    |> build(overrides)
    |> MyApp.Repo.insert!()
  end

  @doc """
  Builds `count` structs for `factory_name` and returns them as a list.

  Each element is built independently, so sequence-driven defaults (such as
  the `:user` factory's email) stay unique across the list. A `count` of `0`
  returns `[]`.
  """
  @spec build_list(non_neg_integer(), factory_name(), overrides()) :: [struct()]
  def build_list(count, factory_name, overrides \\ []) when is_integer(count) and count >= 0 do
    Enum.map(1..count//1, fn _i -> build(factory_name, overrides) end)
  end

  @doc """
  Persists `count` structs for `factory_name` and returns the persisted list.

  Each record is inserted in its own `Task`, so insertion runs concurrently
  while sequence values and assigned ids remain unique. Results are returned in
  the order requested. A `count` of `0` returns `[]`.
  """
  @spec insert_list(non_neg_integer(), factory_name(), overrides()) :: [struct()]
  def insert_list(count, factory_name, overrides \\ []) when is_integer(count) and count >= 0 do
    1..count//1
    |> Enum.map(fn _i -> Task.async(fn -> insert(factory_name, overrides) end) end)
    |> Task.await_many(:infinity)
  end

  @doc """
  Returns the factory's fields as a plain map with the `:id` key removed.

  The result is suitable for feeding into a request or changeset. Associations
  are still resolved, so e.g. `params_for(:post)` contains the `:user_id` of a
  freshly persisted user.
  """
  @spec params_for(factory_name(), overrides()) :: map()
  def params_for(factory_name, overrides \\ []) do
    factory_name
    |> build(overrides)
    |> Map.from_struct()
    |> Map.delete(:id)
    |> Map.delete(:__meta__)
  end

  # Builds the default struct for a factory. `overrides` are inspected so that
  # supplied associations skip the work of persisting a parent record.
  @spec defaults(factory_name(), overrides()) :: struct()
  defp defaults(:user, _overrides) do
    struct(MyApp.User, %{
      name: sequence(:name, &"User #{&1}"),
      email: sequence(:email, &"user#{&1}@example.com")
    })
  end

  defp defaults(:post, overrides) do
    user_id =
      case Keyword.fetch(overrides, :user_id) do
        {:ok, user_id} -> user_id
        :error -> insert(:user).id
      end

    struct(MyApp.Post, %{
      title: sequence(:title, &"Post #{&1}"),
      body: "Some post body.",
      user_id: user_id
    })
  end

  defp defaults(factory_name, _overrides) do
    raise ArgumentError, "no factory defined for #{inspect(factory_name)}"
  end
end