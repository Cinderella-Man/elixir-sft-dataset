# Fill in the middle: `PriorityBiMap.handle_call/3` (the `:put` clause)

Implement the `handle_call/3` clause that handles the `{:put, key, value, priority}`
message. It must resolve conflicts by priority and keep the structure a true
bijection.

The state is a map `%{forward: %{}, reverse: %{}, prio: %{}}` where `forward` maps
`key => value`, `reverse` maps `value => key`, and `prio` maps `key => priority`.

The clause must:

- Determine the **key-side conflict**: the pair currently sitting at `key`. Look up
  `key` in `forward`. If it maps to the exact same `value`, there is no key-side
  conflict; if it maps to a *different* value `oldv`, the conflicting pair is
  `{key, oldv}` with its stored priority (from `prio`); if `key` is absent, there is
  no key-side conflict.
- Determine the **value-side conflict**: the pair currently sitting at `value`. Look
  up `value` in `reverse`. If it maps to the exact same `key`, there is no value-side
  conflict; if it maps to a *different* key `oldk`, the conflicting pair is
  `{oldk, value}` with its stored priority (from `prio` at `oldk`); if `value` is
  absent, there is no value-side conflict.
- Collect the non-nil conflicts. Then:
  - **No conflicts** (the same pair is already present, so only its priority changes,
    or both slots are free): install the pair and reply `{:ok, []}`.
  - **Conflicts exist and `priority` is strictly greater than every conflicting
    pair's priority**: evict each conflicting pair (using `evict/3`), install the new
    pair (using `install/4`), and reply `{:ok, evicted}` where `evicted` is the list
    of displaced `{key, value}` pairs.
  - **Otherwise** (some conflict's priority is greater than or equal to `priority`,
    including ties): reject the put as a complete no-op and reply
    `{:error, :rejected}` with the state unchanged.

Use the existing private helpers `install/4` and `evict/3`. The other `handle_call/3`
clauses are already implemented and must not change.

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

  @spec priority(GenServer.server(), term()) :: {:ok, integer()} | :error
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
    # TODO
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