# Implement `handle_call/3` for `BoundedBiMap`

`BoundedBiMap` is a `GenServer` that maintains a bounded, bijective (bidirectional)
mapping between keys and values with least-recently-used (LRU) eviction. Its state is a
map with these fields:

- `:forward` — a `key => value` map,
- `:reverse` — a `value => key` map (the inverse of `:forward`),
- `:access` — a `key => tick` map recording the recency of each key,
- `:clock` — a monotonically increasing integer "tick" used as the recency clock,
- `:capacity` — the maximum number of pairs allowed.

The client API delegates every operation to `GenServer.call/2`, so all behavior lives in
`handle_call/3`. Two private helpers are already provided: `touch/2` (refreshes a key's
recency by writing the current clock into `:access` and advancing the clock) and
`evict_lru/3` (given the forward, reverse, and access maps, removes the least-recently-used
pair from all three and returns the updated `{forward, reverse, access}`).

Implement every clause of `handle_call/3`:

- **`{:put, key, value}`** — Insert or update the association while preserving the
  bijection, then reply `:ok`. First remember whether `key` already existed. Then do
  bijection maintenance: (1) if `key` currently maps to a *different* value, delete that old
  value from `:reverse`; (2) if `value` currently maps to a *different* key, remove that old
  key entirely from both `:forward` and `:access`. After maintenance, if `key` is a
  brand-new key (did not exist before) and the forward map is already at `:capacity`, evict
  the least-recently-used pair via `evict_lru/3`. Finally install the new pair: put
  `key => value` in `:forward`, `value => key` in `:reverse`, and `key => clock` in
  `:access`, and advance `:clock` by 1. Reply `:ok` with the updated state.

- **`{:get_by_key, key}`** — If `key` is present in `:forward`, reply `{:ok, value}` and
  refresh that key's recency with `touch/2`. Otherwise reply `:error` with the state
  unchanged.

- **`{:get_by_value, value}`** — If `value` is present in `:reverse`, reply `{:ok, key}` and
  refresh that key's recency with `touch/2`. Otherwise reply `:error` with the state
  unchanged.

- **`{:delete, key}`** — If `key` is present, remove it and its associated value from all
  three maps (`:forward`, `:reverse`, `:access`) and reply `:ok`. If `key` is absent, it is
  a harmless no-op: reply `:ok` with the state unchanged.

- **`:size`** — Reply with the current number of pairs (the size of `:forward`), state
  unchanged.

- **`:keys_by_recency`** — Reply with the list of keys ordered least-recently-used first and
  most-recently-used last, by sorting `:access` entries by their tick. State unchanged.

```elixir
defmodule BoundedBiMap do
  @moduledoc """
  A GenServer maintaining a bijective bidirectional mapping bounded to a fixed
  `:capacity`, with least-recently-used (LRU) eviction.

  State holds a forward map (`key => value`), a reverse map (`value => key`), and
  an access map (`key => tick`) tracking recency via a monotonic clock. Every
  `put` and every successful `get_by_key`/`get_by_value` refreshes a pair's
  recency. When a brand-new key is inserted while the map is at capacity, the
  least-recently-used pair is evicted first.

  Keys and values may be any term.
  """

  use GenServer

  ## Client API

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    {name, opts} = Keyword.pop(opts, :name)
    {capacity, opts} = Keyword.pop(opts, :capacity)
    GenServer.start_link(__MODULE__, capacity, [name: name] ++ opts)
  end

  @doc "Stores the `key`<->`value` pair, evicting the LRU entry when at capacity. Returns `:ok`."
  @spec put(GenServer.server(), term(), term()) :: :ok
  def put(name, key, value), do: GenServer.call(name, {:put, key, value})

  @spec get_by_key(GenServer.server(), term()) :: {:ok, term()} | :error
  def get_by_key(name, key), do: GenServer.call(name, {:get_by_key, key})

  @spec get_by_value(GenServer.server(), term()) :: {:ok, term()} | :error
  def get_by_value(name, value), do: GenServer.call(name, {:get_by_value, value})

  @spec delete(GenServer.server(), term()) :: :ok
  def delete(name, key), do: GenServer.call(name, {:delete, key})

  @spec size(GenServer.server()) :: non_neg_integer()
  def size(name), do: GenServer.call(name, :size)

  @spec keys_by_recency(GenServer.server()) :: [term()]
  def keys_by_recency(name), do: GenServer.call(name, :keys_by_recency)

  ## Server callbacks

  @impl true
  def init(capacity) when is_integer(capacity) and capacity > 0 do
    {:ok, %{forward: %{}, reverse: %{}, access: %{}, clock: 0, capacity: capacity}}
  end

  def handle_call({:put, key, value}, _from, state) do
    # TODO
  end

  ## Helpers

  defp touch(state, key) do
    %{state | access: Map.put(state.access, key, state.clock), clock: state.clock + 1}
  end

  defp evict_lru(f, r, a) do
    {lru_key, _tick} = Enum.min_by(a, fn {_k, tick} -> tick end)
    value = Map.fetch!(f, lru_key)
    {Map.delete(f, lru_key), Map.delete(r, value), Map.delete(a, lru_key)}
  end
end
```