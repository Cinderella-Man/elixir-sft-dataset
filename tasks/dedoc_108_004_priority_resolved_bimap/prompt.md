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
defmodule PriorityBiMap do
  use GenServer

  ## Client API

  def start_link(opts) do
    {name, opts} = Keyword.pop(opts, :name)
    GenServer.start_link(__MODULE__, :ok, [name: name] ++ opts)
  end

  def put(name, key, value, priority) do
    GenServer.call(name, {:put, key, value, priority})
  end

  def get_by_key(name, key), do: GenServer.call(name, {:get_by_key, key})

  def get_by_value(name, value), do: GenServer.call(name, {:get_by_value, value})

  def priority(name, key), do: GenServer.call(name, {:priority, key})

  def delete(name, key), do: GenServer.call(name, {:delete, key})

  ## Server callbacks

  @impl true
  def init(:ok) do
    # forward: key => value, reverse: value => key, prio: key => priority
    {:ok, %{forward: %{}, reverse: %{}, prio: %{}}}
  end

  @impl true
  def handle_call({:put, key, value, priority}, _from, state) do
    %{forward: f, reverse: r, prio: p} = state

    # The pair currently sitting at `key`, if it binds a *different* value.
    key_conflict =
      case Map.fetch(f, key) do
        {:ok, ^value} -> nil
        {:ok, oldv} -> {key, oldv, Map.fetch!(p, key)}
        :error -> nil
      end

    # The pair currently sitting at `value`, if it binds a *different* key.
    value_conflict =
      case Map.fetch(r, value) do
        {:ok, ^key} -> nil
        {:ok, oldk} -> {oldk, value, Map.fetch!(p, oldk)}
        :error -> nil
      end

    conflicts = Enum.reject([key_conflict, value_conflict], &is_nil/1)

    cond do
      conflicts == [] ->
        # Same pair (priority update) or a fully free slot: install.
        {:reply, {:ok, []}, install(state, key, value, priority)}

      priority > Enum.max(Enum.map(conflicts, fn {_k, _v, cp} -> cp end)) ->
        state = Enum.reduce(conflicts, state, fn {ck, cv, _cp}, acc -> evict(acc, ck, cv) end)
        evicted = Enum.map(conflicts, fn {ck, cv, _cp} -> {ck, cv} end)
        {:reply, {:ok, evicted}, install(state, key, value, priority)}

      true ->
        {:reply, {:error, :rejected}, state}
    end
  end

  def handle_call({:get_by_key, key}, _from, state) do
    {:reply, Map.fetch(state.forward, key), state}
  end

  def handle_call({:get_by_value, value}, _from, state) do
    {:reply, Map.fetch(state.reverse, value), state}
  end

  def handle_call({:priority, key}, _from, state) do
    {:reply, Map.fetch(state.prio, key), state}
  end

  def handle_call({:delete, key}, _from, state) do
    case Map.fetch(state.forward, key) do
      {:ok, value} -> {:reply, :ok, evict(state, key, value)}
      :error -> {:reply, :ok, state}
    end
  end

  ## Helpers

  defp install(state, key, value, priority) do
    %{
      state
      | forward: Map.put(state.forward, key, value),
        reverse: Map.put(state.reverse, value, key),
        prio: Map.put(state.prio, key, priority)
    }
  end

  defp evict(state, key, value) do
    %{
      state
      | forward: Map.delete(state.forward, key),
        reverse: Map.delete(state.reverse, value),
        prio: Map.delete(state.prio, key)
    }
  end
end
```
