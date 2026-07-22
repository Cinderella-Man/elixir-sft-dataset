defmodule Factory do
  @moduledoc """
  A lightweight, self-contained test-data factory with **bulk generation**.

  Adds `build_list/2,3`, `insert_list/2,3` (concurrent), and `params_for/1,2`
  on top of the usual `build`, `insert`, and `sequence` API.

  ## Usage

      Factory.build_list(3, :user)
      Factory.insert_list(100, :user)          # concurrent inserts
      Factory.params_for(:user, name: "Ada")   # plain map, no :id
  """

  @compile {:no_warn_undefined, MyApp.Repo}

  @agent __MODULE__.SequenceAgent

  # -------------------------------------------------------------------------
  # Agent lifecycle + sequences
  # -------------------------------------------------------------------------

  @doc "Starts the named Agent backing all sequence counters."
  def start do
    Agent.start_link(fn -> %{} end, name: @agent)
  end

  @doc "Returns the next value for the named sequence."
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
  # Singular build / insert
  # -------------------------------------------------------------------------

  @doc "Builds a struct for `name` without touching the database."
  def build(name), do: build(name, [])

  @doc "Builds a struct for `name`, merging `overrides`."
  def build(name, overrides) do
    name
    |> factory()
    |> merge_overrides(overrides)
    |> resolve_thunks()
  end

  @doc "Builds and persists a struct for `name`."
  def insert(name), do: insert(name, [])

  @doc "Builds with `overrides`, then persists via `MyApp.Repo`."
  def insert(name, overrides) do
    name
    |> build(overrides)
    |> MyApp.Repo.insert!()
  end

  # -------------------------------------------------------------------------
  # Bulk build / insert
  # -------------------------------------------------------------------------

  @doc "Builds a list of `count` structs for `name`."
  def build_list(count, name), do: build_list(count, name, [])

  @doc "Builds a list of `count` structs for `name`, each with `overrides`."
  def build_list(count, name, overrides) when is_integer(count) and count >= 0 do
    Enum.map(1..count//1, fn _ -> build(name, overrides) end)
  end

  @doc "Persists `count` structs for `name` concurrently."
  def insert_list(count, name), do: insert_list(count, name, [])

  @doc "Persists `count` structs for `name` concurrently, each with `overrides`."
  def insert_list(count, name, overrides) when is_integer(count) and count >= 0 do
    1..count//1
    |> Enum.map(fn _ -> Task.async(fn -> insert(name, overrides) end) end)
    |> Task.await_many()
  end

  # -------------------------------------------------------------------------
  # params_for
  # -------------------------------------------------------------------------

  @doc "Returns a plain map of `name`'s fields (no struct, no `:id`)."
  def params_for(name), do: params_for(name, [])

  @doc "Returns a plain map of `name`'s fields with `overrides`, minus `:id`."
  def params_for(name, overrides) do
    name
    |> build(overrides)
    |> Map.from_struct()
    |> Map.delete(:id)
  end

  # -------------------------------------------------------------------------
  # Internal helpers
  # -------------------------------------------------------------------------

  defp merge_overrides(base, []), do: base
  defp merge_overrides(base, overrides), do: struct(base, overrides)

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

  defp ensure_agent_started do
    case Process.whereis(@agent) do
      nil -> Agent.start_link(fn -> %{} end, name: @agent)
      _pid -> :ok
    end
  end

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
      user_id: fn -> insert(:user).id end
    )
  end

  defp factory(name) do
    raise ArgumentError, "No factory defined for #{inspect(name)}."
  end
end