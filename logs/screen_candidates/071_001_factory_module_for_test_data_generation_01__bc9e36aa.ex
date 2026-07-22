defmodule Factory do
  @moduledoc """
  A small, self-contained test-data factory in the spirit of `ExMachina`.

  Factories are declared with the `define/2` macro, which expands into a clause of the
  private `factory/1` function returning the base struct for that factory name.

  The public API is:

    * `build/1`, `build/2` — construct a struct in memory (no repo writes for the struct
      itself, though associations that need a database id are inserted eagerly);
    * `insert/1`, `insert/2` — build then persist through `MyApp.Repo.insert!/1`;
    * `sequence/2` — obtain the next value of an independent, named counter.

  Sequence counters live in a named `Agent` (`Factory.Sequences`) that is started once,
  either explicitly via `start/0` or lazily on first use. Because the counters are kept in
  a single process and incremented with `Agent.get_and_update/3`, values are unique across
  the whole test run even when tests run with `async: true`.

  ## Association strategy

  Associations that are plain embedded structs are built eagerly and inlined by the factory
  definition. Associations that require a database id (such as the `:post` factory's
  `user_id`) are inserted via `Factory.insert/1` while the parent is being built, so that
  `build(:post)` yields a post pointing at a real, persisted user. Supplying the foreign key
  explicitly (`build(:post, user_id: 7)`) suppresses that insert entirely.
  """

  defmodule User do
    @moduledoc """
    Schema-like struct used by the `:user` factory.
    """

    defstruct [:id, :name, :email]

    @type t :: %__MODULE__{id: integer() | nil, name: String.t() | nil, email: String.t() | nil}
  end

  defmodule Post do
    @moduledoc """
    Schema-like struct used by the `:post` factory.
    """

    defstruct [:id, :title, :body, :user_id]

    @type t :: %__MODULE__{
            id: integer() | nil,
            title: String.t() | nil,
            body: String.t() | nil,
            user_id: integer() | nil
          }
  end

  @agent Factory.Sequences

  @typedoc "The name of a declared factory, e.g. `:user`."
  @type factory_name :: atom()

  @typedoc "Field overrides applied on top of a built struct."
  @type overrides :: keyword()

  @doc """
  Declares a factory named `name` whose base attributes are given by `block`.

  The block must evaluate to a struct. It is re-evaluated on every `build/1` call, so
  `sequence/2` calls and association inserts inside it behave as expected.

      define :user do
        %User{name: sequence(:name, &"User \#{&1}"), email: sequence(:email, &"user\#{&1}@ex.com")}
      end
  """
  @spec define(factory_name(), keyword()) :: Macro.t()
  defmacro define(name, do: block) do
    quote do
      defp factory(unquote(name)), do: unquote(block)
    end
  end

  define :user do
    %User{
      name: sequence(:user_name, &"User #{&1}"),
      email: sequence(:user_email, &"user#{&1}@example.com")
    }
  end

  define :post do
    %Post{
      title: sequence(:post_title, &"Post #{&1}"),
      body: "Post body",
      user_id: insert(:user).id
    }
  end

  @doc """
  Starts the sequence `Agent` if it is not already running.

  Safe to call more than once and from multiple processes; returns `:ok` either way. Calling
  it is optional — `sequence/2` starts the agent lazily on first use.
  """
  @spec start() :: :ok
  def start do
    case Agent.start_link(fn -> %{} end, name: @agent) do
      {:ok, _pid} -> :ok
      {:error, {:already_started, _pid}} -> :ok
    end
  end

  @doc """
  Returns the next value of the sequence `name`, formatted by `formatter`.

  Each `name` has its own counter starting at `1`; `formatter` receives the raw integer and
  returns the value handed back to the caller. Counters are global to the test run, so
  values remain unique under `async: true`.

      iex> Factory.sequence(:email, &"user\#{&1}@example.com")
      "user1@example.com"
  """
  @spec sequence(atom(), (pos_integer() -> value)) :: value when value: term()
  def sequence(name, formatter) when is_atom(name) and is_function(formatter, 1) do
    ensure_started()

    n = Agent.get_and_update(@agent, fn state -> next(state, name) end)

    formatter.(n)
  end

  @doc """
  Builds the struct for `factory_name` without persisting it.

  Associations requiring a database id are still inserted (see the module docs).

      iex> %Factory.User{} = Factory.build(:user)
  """
  @spec build(factory_name()) :: struct()
  def build(factory_name) when is_atom(factory_name), do: build(factory_name, [])

  @doc """
  Builds the struct for `factory_name` and merges `overrides` into it.

  Overrides are applied lazily: any field present in `overrides` is taken from the keyword
  list and the factory never computes a value for it. In particular,
  `build(:post, user_id: id)` does not insert an associated user.

      iex> Factory.build(:user, name: "Ada").name
      "Ada"
  """
  @spec build(factory_name(), overrides()) :: struct()
  def build(factory_name, overrides) when is_atom(factory_name) and is_list(overrides) do
    factory_name
    |> lazy_factory(overrides)
    |> struct!(overrides)
  end

  @doc """
  Builds the struct for `factory_name` and persists it with `MyApp.Repo.insert!/1`.

      iex> Factory.insert(:user).id
  """
  @spec insert(factory_name()) :: struct()
  def insert(factory_name) when is_atom(factory_name), do: insert(factory_name, [])

  @doc """
  Builds the struct for `factory_name` with `overrides` and persists it via
  `MyApp.Repo.insert!/1`, returning the struct as stored by the repo.

      iex> Factory.insert(:post, title: "Hello").title
      "Hello"
  """
  @spec insert(factory_name(), overrides()) :: struct()
  def insert(factory_name, overrides) when is_atom(factory_name) and is_list(overrides) do
    factory_name
    |> build(overrides)
    |> MyApp.Repo.insert!()
  end

  # Builds the base struct, skipping association work whose foreign key was overridden.
  # `:post` is the only factory with a database-backed association today; overriding
  # `:user_id` means the caller already has a user, so we must not insert another one.
  @spec lazy_factory(factory_name(), overrides()) :: struct()
  defp lazy_factory(:post, overrides) do
    if Keyword.has_key?(overrides, :user_id) do
      %Post{title: sequence(:post_title, &"Post #{&1}"), body: "Post body"}
    else
      factory(:post)
    end
  end

  defp lazy_factory(factory_name, _overrides), do: factory(factory_name)

  @spec ensure_started() :: :ok
  defp ensure_started do
    case Process.whereis(@agent) do
      nil -> start_agent()
      _pid -> :ok
    end
  end

  # Started outside the caller's supervision tree so the counters survive individual tests.
  @spec start_agent() :: :ok
  defp start_agent do
    case Agent.start(fn -> %{} end, name: @agent) do
      {:ok, _pid} -> :ok
      {:error, {:already_started, _pid}} -> :ok
    end
  end

  @spec next(%{optional(atom()) => pos_integer()}, atom()) ::
          {pos_integer(), %{optional(atom()) => pos_integer()}}
  defp next(state, name) do
    n = Map.get(state, name, 0) + 1
    {n, Map.put(state, name, n)}
  end
end