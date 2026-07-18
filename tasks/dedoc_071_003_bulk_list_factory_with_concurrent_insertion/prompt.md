# Document this module

Below is a complete, working, tested Elixir module. Its behavior is correct
and must not change — but every piece of documentation has been stripped.

Add the missing documentation and typespecs:

- a `@moduledoc` that explains what the module does and how it is used,
- a `@doc` for every public function,
- a `@spec` for every public function (add `@type`s where they make the
  specs clearer).

Do not change any behavior: every function clause, guard, and expression
must keep working exactly as it does now. Do not rename anything, do not
"improve" the code, and do not add or remove functions. Give me the
complete documented module in a single file.

## The module

```elixir
defmodule Factory do
  @compile {:no_warn_undefined, MyApp.Repo}

  @agent __MODULE__.SequenceAgent

  # -------------------------------------------------------------------------
  # Agent lifecycle + sequences
  # -------------------------------------------------------------------------

  def start do
    Agent.start_link(fn -> %{} end, name: @agent)
  end

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

  def build(name), do: build(name, [])

  def build(name, overrides) do
    name
    |> factory()
    |> merge_overrides(overrides)
    |> resolve_thunks()
  end

  def insert(name), do: insert(name, [])

  def insert(name, overrides) do
    name
    |> build(overrides)
    |> MyApp.Repo.insert!()
  end

  # -------------------------------------------------------------------------
  # Bulk build / insert
  # -------------------------------------------------------------------------

  def build_list(count, name), do: build_list(count, name, [])

  def build_list(count, name, overrides) when is_integer(count) and count >= 0 do
    Enum.map(1..count//1, fn _ -> build(name, overrides) end)
  end

  def insert_list(count, name), do: insert_list(count, name, [])

  def insert_list(count, name, overrides) when is_integer(count) and count >= 0 do
    1..count//1
    |> Enum.map(fn _ -> Task.async(fn -> insert(name, overrides) end) end)
    |> Task.await_many()
  end

  # -------------------------------------------------------------------------
  # params_for
  # -------------------------------------------------------------------------

  def params_for(name), do: params_for(name, [])

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
      nil ->
        Agent.start_link(fn -> %{} end, name: @agent)
        :ok

      _pid ->
        :ok
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
```
