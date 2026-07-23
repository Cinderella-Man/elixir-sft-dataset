# Restore the documentation

The module below works and is fully tested — its behavior is final. What it
lost is every piece of documentation. Put it back:

- a `@moduledoc` covering purpose and usage,
- a `@doc` on each public function,
- a `@spec` on each public function (plus `@type`s where they clarify).

And keep your hands off the code itself: no renames, no refactors, no added
or removed functions, identical behavior everywhere. Return the whole
documented module in one file.

## The module

```elixir
defmodule Factory do
  # MyApp.Repo is provided by the host application and is not available at
  # compile time of this file. Suppress the "undefined or private" warning.
  @compile {:no_warn_undefined, MyApp.Repo}

  @agent __MODULE__.SequenceAgent

  # -------------------------------------------------------------------------
  # Agent lifecycle
  # -------------------------------------------------------------------------

  def start do
    Agent.start(fn -> %{} end, name: @agent)
  end

  # -------------------------------------------------------------------------
  # Sequences
  # -------------------------------------------------------------------------

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

  def build(factory_name), do: build(factory_name, [])

  def build(factory_name, overrides) do
    factory_name
    |> factory()
    |> merge_overrides(overrides)
    |> resolve_thunks()
  end

  def insert(factory_name), do: insert(factory_name, [])

  def insert(factory_name, overrides) do
    factory_name
    |> build(overrides)
    |> MyApp.Repo.insert!()
  end

  # -------------------------------------------------------------------------
  # Internal helpers
  # -------------------------------------------------------------------------

  defp merge_overrides(base, []), do: base
  defp merge_overrides(base, overrides), do: struct(base, overrides)

  # Walk every field; call any zero-arity function (thunk) to produce its
  # value. Thunks are only evaluated for fields that were NOT overridden,
  # since merge_overrides replaces function values before this step runs.
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
