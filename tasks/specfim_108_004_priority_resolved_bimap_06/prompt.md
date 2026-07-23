# Reconstruct the missing typespec

In the otherwise-complete module below, the `@spec` for
`priority/2` has been removed; `# TODO: @spec` holds its place.
Write that one attribute — a `@spec` for `priority/2` faithful to
the arguments, guards, and every return shape the code can actually
produce. Nothing else changes.

## The module with the `@spec` for `priority/2` missing

```elixir
defmodule PriorityBiMap do
  @moduledoc """
  A GenServer maintaining a bijective bidirectional mapping where each pair
  carries an integer priority and conflicts are resolved by priority.

  A `put/4` may conflict with the pair currently at `key` and/or the pair
  currently at `value`. It succeeds only when its priority is strictly greater
  than every conflicting pair's priority, in which case the conflicting pairs are
  evicted and reported; otherwise (including ties) it is rejected and nothing
  changes. Re-putting the exact same pair simply updates its stored priority.

  Keys and values may be any term; priorities are integers.
  """

  use GenServer

  ## Client API

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    {name, opts} = Keyword.pop(opts, :name)
    GenServer.start_link(__MODULE__, :ok, [name: name] ++ opts)
  end

  @doc "Stores the `key`<->`value` pair at `priority`, resolving conflicts by priority."
  @spec put(GenServer.server(), term(), term(), integer()) ::
          {:ok, [{term(), term()}]} | {:error, :rejected}
  def put(name, key, value, priority) do
    GenServer.call(name, {:put, key, value, priority})
  end

  @spec get_by_key(GenServer.server(), term()) :: {:ok, term()} | :error
  def get_by_key(name, key), do: GenServer.call(name, {:get_by_key, key})

  @spec get_by_value(GenServer.server(), term()) :: {:ok, term()} | :error
  def get_by_value(name, value), do: GenServer.call(name, {:get_by_value, value})

  # TODO: @spec
  def priority(name, key), do: GenServer.call(name, {:priority, key})

  @spec delete(GenServer.server(), term()) :: :ok
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

Reply with the `@spec` attribute alone, however many lines it needs —
not the module.
