defmodule Factory do
  @moduledoc """
  A small, self-contained test-data factory in the spirit of `ExMachina`, with
  trait composition layered on top of the usual `build/insert` API.

  ## Concepts

    * **Factory** — a named blueprint (`:user`, `:post`) that knows the struct
      module it builds and a keyword list of default field values.
    * **Trait** — a named, reusable overlay of field values for a given factory,
      declared via `trait/2` (e.g. `{:user, :admin}` sets `role` to `"admin"`).
    * **Sequence** — a monotonically increasing per-name counter used to build
      unique values (`Factory.sequence(:email, &"user-#{&1}@example.com")`).

  ## Precedence

  Values are merged from lowest to highest priority:

      factory defaults -> traits (left to right) -> explicit overrides

  ## Usage

      Factory.start()

      Factory.build(:user)
      Factory.build(:user, name: "Ada")
      Factory.build(:user, [:admin])
      Factory.build(:user, [:admin, :inactive], name: "Ada")

      Factory.insert(:post, [:published], title: "Hello")

  `build/2` accepts either a keyword list of overrides or a list of bare trait
  atoms and disambiguates the two: a proper keyword list is treated as
  overrides, a list of atoms as traits. The empty list `[]` is ambiguous and is
  treated as "no overrides", which is equivalent to "no traits".

  Sequences are backed by a named `Agent`, so they remain unique across the whole
  test run even under concurrent (`async: true`) access. Call `start/0` once
  before using any other function in this module.
  """

  @compile {:no_warn_undefined, MyApp.Repo}
  @compile {:no_warn_undefined, MyApp.User}
  @compile {:no_warn_undefined, MyApp.Post}

  @agent __MODULE__.Sequences

  @typedoc "The name of a factory, e.g. `:user`."
  @type factory_name :: atom()

  @typedoc "The name of a trait, e.g. `:admin`."
  @type trait_name :: atom()

  @typedoc "A keyword list of explicit field overrides."
  @type overrides :: keyword()

  @doc """
  Starts the named `Agent` that backs the sequence counters.

  Returns the raw `Agent.start_link/2` result, so `{:error, {:already_started,
  pid}}` is passed through untouched and calling this more than once is safe.

  Call this once (e.g. from `setup_all`) before any other factory function.
  """
  @spec start() :: {:ok, pid()} | {:error, term()}
  def start do
    Agent.start_link(fn -> %{} end, name: @agent)
  end

  @doc """
  Returns the next value of the named sequence.

  `formatter_fn` is called with a monotonically increasing integer starting at
  `1`. Each `name` keeps its own independent counter, and increments are
  serialized through the sequence `Agent`, so values stay unique even when tests
  run concurrently.

  ## Examples

      Factory.sequence(:email, fn n -> "user-#{n}@example.com" end)
      #=> "user-1@example.com"

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
  Builds a struct for `factory_name` using only the factory defaults.

  Nothing is persisted. Note that building a `:post` without a `user_id`
  override *does* insert an associated user, since the association must exist.
  """
  @spec build(factory_name()) :: struct()
  def build(factory_name) when is_atom(factory_name) do
    build(factory_name, [], [])
  end

  @doc """
  Builds a struct for `factory_name` from either overrides or traits.

  `opts` is either a keyword list of field overrides (`name: "Ada"`) or a list of
  bare trait atoms (`[:admin]`). A proper keyword list is treated as overrides;
  a list of atoms is treated as traits. `[]` means "no overrides".

  ## Examples

      Factory.build(:user, name: "Ada")
      Factory.build(:user, [:admin])

  """
  @spec build(factory_name(), overrides() | [trait_name()]) :: struct()
  def build(factory_name, opts) when is_atom(factory_name) and is_list(opts) do
    {traits, overrides} = split_opts(opts)
    build(factory_name, traits, overrides)
  end

  @doc """
  Builds a struct for `factory_name`, applying `traits` and then `overrides`.

  Values merge as: factory defaults -> traits (left to right) -> overrides.
  Raises `ArgumentError` for an unknown factory or an unknown trait.

  ## Examples

      Factory.build(:user, [:admin, :inactive], name: "Ada")

  """
  @spec build(factory_name(), [trait_name()], overrides()) :: struct()
  def build(factory_name, traits, overrides)
      when is_atom(factory_name) and is_list(traits) and is_list(overrides) do
    validate_traits!(traits, overrides)

    trait_attrs = Enum.flat_map(traits, &trait!(factory_name, &1))

    attrs =
      factory_name
      |> defaults(overrides)
      |> merge(trait_attrs)
      |> merge(overrides)

    struct!(module_for(factory_name), attrs)
  end

  @doc """
  Builds a struct for `factory_name` from the factory defaults and persists it
  via `MyApp.Repo.insert!/1`, returning the persisted struct.
  """
  @spec insert(factory_name()) :: struct()
  def insert(factory_name) when is_atom(factory_name) do
    insert(factory_name, [], [])
  end

  @doc """
  Builds a struct for `factory_name` from either overrides or traits and
  persists it via `MyApp.Repo.insert!/1`, returning the persisted struct.

  `opts` follows the same disambiguation rules as `build/2`.
  """
  @spec insert(factory_name(), overrides() | [trait_name()]) :: struct()
  def insert(factory_name, opts) when is_atom(factory_name) and is_list(opts) do
    {traits, overrides} = split_opts(opts)
    insert(factory_name, traits, overrides)
  end

  @doc """
  Builds a struct for `factory_name` with `traits` and `overrides` applied, then
  persists it via `MyApp.Repo.insert!/1`, returning the persisted struct.
  """
  @spec insert(factory_name(), [trait_name()], overrides()) :: struct()
  def insert(factory_name, traits, overrides)
      when is_atom(factory_name) and is_list(traits) and is_list(overrides) do
    factory_name
    |> build(traits, overrides)
    |> MyApp.Repo.insert!()
  end

  @doc """
  Returns the overlay of field values for `trait_name` on `factory_name`.

  Each clause returns a keyword list that is merged over the factory defaults.
  Unknown traits fall through to `trait!/2`, which raises `ArgumentError`.
  """
  @spec trait(factory_name(), trait_name()) :: overrides() | :error
  def trait(:user, :admin), do: [role: "admin"]
  def trait(:user, :inactive), do: [active: false]
  def trait(:post, :published), do: [published: true]
  def trait(factory_name, trait_name) when is_atom(factory_name) and is_atom(trait_name) do
    :error
  end

  # -- Factory definitions ---------------------------------------------------

  @spec module_for(factory_name()) :: module()
  defp module_for(:user), do: MyApp.User
  defp module_for(:post), do: MyApp.Post

  defp module_for(factory_name) do
    raise ArgumentError, "unknown factory #{inspect(factory_name)}"
  end

  # Defaults may depend on the caller's overrides: `:post` only creates its
  # associated user when no `user_id` was supplied.
  @spec defaults(factory_name(), overrides()) :: overrides()
  defp defaults(:user, _overrides) do
    [
      name: sequence(:user_name, fn n -> "User #{n}" end),
      email: sequence(:user_email, fn n -> "user-#{n}@example.com" end),
      role: "member",
      active: true
    ]
  end

  defp defaults(:post, overrides) do
    user_id =
      if Keyword.has_key?(overrides, :user_id) do
        nil
      else
        insert(:user).id
      end

    [
      title: sequence(:post_title, fn n -> "Post #{n}" end),
      body: sequence(:post_body, fn n -> "Body of post #{n}" end),
      published: false,
      user_id: user_id
    ]
  end

  defp defaults(factory_name, _overrides) do
    raise ArgumentError, "unknown factory #{inspect(factory_name)}"
  end

  # -- Internals -------------------------------------------------------------

  # `[]` is both a valid keyword list and a valid trait list; treating it as
  # overrides is equivalent to treating it as traits.
  @spec split_opts(overrides() | [trait_name()]) :: {[trait_name()], overrides()}
  defp split_opts(opts) do
    if Keyword.keyword?(opts) do
      {[], opts}
    else
      {opts, []}
    end
  end

  @spec validate_traits!([trait_name()], overrides()) :: :ok
  defp validate_traits!(traits, overrides) do
    unless Enum.all?(traits, &is_atom/1) do
      raise ArgumentError, "traits must be a list of atoms, got: #{inspect(traits)}"
    end

    unless Keyword.keyword?(overrides) do
      raise ArgumentError, "overrides must be a keyword list, got: #{inspect(overrides)}"
    end

    :ok
  end

  @spec trait!(factory_name(), trait_name()) :: overrides()
  defp trait!(factory_name, trait_name) do
    case trait(factory_name, trait_name) do
      :error ->
        raise ArgumentError,
              "unknown trait #{inspect(trait_name)} for factory #{inspect(factory_name)}"

      attrs when is_list(attrs) ->
        attrs
    end
  end

  @spec merge(overrides(), overrides()) :: overrides()
  defp merge(base, extra), do: Keyword.merge(base, extra)
end