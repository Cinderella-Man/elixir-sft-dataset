# Implement the missing function

Below is the complete specification of a task, followed by a working,
fully tested module that solves it — except that `init` has been
removed: every clause body is blanked to `# TODO`. Implement exactly that
function so the whole module passes the task's full test suite again.
Change nothing else — every other function, attribute, and clause must
stay exactly as shown.

## The task

# Capacity-Bounded BiMap with LRU Eviction

Write me an Elixir GenServer module called `BoundedBiMap` that maintains a **bidirectional mapping** (a bijection between keys and values, exactly like a classic BiMap) but with a **fixed maximum number of pairs** enforced by **least-recently-used (LRU) eviction**. Memory is bounded by construction: once the map is full, inserting a brand-new key evicts the least-recently-used pair to make room.

## Public API

- `BoundedBiMap.start_link(opts)` — starts the process. It must accept a `:name` option used to register the process and a required `:capacity` option (a positive integer, the maximum number of pairs). All other functions take the name (or any valid GenServer server reference) as their first argument. Return the usual `{:ok, pid}`.

- `BoundedBiMap.put(name, key, value)` — inserts or updates the association between `key` and `value`, preserving the bijection. Always returns `:ok`. A `put` counts as **using** the pair (it refreshes recency). Eviction rules:
  - If `key` already maps to a different value, the old value's reverse mapping is removed (standard bijection maintenance) — this is an *update*, not a new key, so it never triggers LRU eviction.
  - If `value` already maps to a different key, that old key is removed entirely (bijection maintenance). This frees a slot, so it may make room without any LRU eviction.
  - If, after the above maintenance, `key` is a **brand-new key** and the map is already at `capacity`, evict the least-recently-used pair (both directions) before installing the new pair.

- `BoundedBiMap.get_by_key(name, key)` — returns `{:ok, value}` if `key` is present, otherwise `:error`. A successful lookup counts as **using** the pair (it refreshes recency, protecting it from the next eviction).

- `BoundedBiMap.get_by_value(name, value)` — returns `{:ok, key}` if `value` is present, otherwise `:error`. A successful lookup also refreshes the pair's recency.

- `BoundedBiMap.delete(name, key)` — removes `key` and its associated value (both directions), freeing a slot. Returns `:ok`. Deleting an absent key is a harmless no-op.

- `BoundedBiMap.size(name)` — returns the current number of pairs.

- `BoundedBiMap.keys_by_recency(name)` — returns the current keys as a list ordered least-recently-used first, most-recently-used last (useful for inspecting the eviction order).

## Semantics

- The structure is always a true bijection: every `get_by_key(name, k)` returning `{:ok, v}` implies `get_by_value(name, v)` returns `{:ok, k}`, and vice versa.
- The number of pairs never exceeds `capacity`.
- Recency is refreshed by **every** `put` and by **every successful** `get_by_key`/`get_by_value`. Overwriting an existing key updates its value and refreshes recency but does **not** change the count, so it never evicts another pair.
- When a new-key insertion at capacity requires eviction, exactly the least-recently-used pair is removed.

Keys and values can be any term. Use only the OTP standard library — no external dependencies. Give me the complete module in a single file.

## The module with `init` missing

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

  def init(capacity) when is_integer(capacity) and capacity > 0 do
    # TODO
  end

  @impl true
  def handle_call({:put, key, value}, _from, state) do
    %{forward: f, reverse: r, access: a, clock: c, capacity: cap} = state

    key_existed = Map.has_key?(f, key)

    # Bijection maintenance step 1: if key rebinds to a new value, orphan old value.
    r =
      case Map.fetch(f, key) do
        {:ok, ^value} -> r
        {:ok, oldv} -> Map.delete(r, oldv)
        :error -> r
      end

    # Bijection maintenance step 2: if value rebinds to a new key, evict old key.
    {f, r, a} =
      case Map.fetch(r, value) do
        {:ok, ^key} -> {f, r, a}
        {:ok, oldk} -> {Map.delete(f, oldk), r, Map.delete(a, oldk)}
        :error -> {f, r, a}
      end

    # LRU eviction only when a genuinely new key would push us past capacity.
    {f, r, a} =
      if not key_existed and map_size(f) >= cap do
        evict_lru(f, r, a)
      else
        {f, r, a}
      end

    f = Map.put(f, key, value)
    r = Map.put(r, value, key)
    a = Map.put(a, key, c)

    {:reply, :ok, %{state | forward: f, reverse: r, access: a, clock: c + 1}}
  end

  def handle_call({:get_by_key, key}, _from, state) do
    case Map.fetch(state.forward, key) do
      {:ok, v} -> {:reply, {:ok, v}, touch(state, key)}
      :error -> {:reply, :error, state}
    end
  end

  def handle_call({:get_by_value, value}, _from, state) do
    case Map.fetch(state.reverse, value) do
      {:ok, k} -> {:reply, {:ok, k}, touch(state, k)}
      :error -> {:reply, :error, state}
    end
  end

  def handle_call({:delete, key}, _from, state) do
    case Map.fetch(state.forward, key) do
      {:ok, v} ->
        new_state = %{
          state
          | forward: Map.delete(state.forward, key),
            reverse: Map.delete(state.reverse, v),
            access: Map.delete(state.access, key)
        }

        {:reply, :ok, new_state}

      :error ->
        {:reply, :ok, state}
    end
  end

  def handle_call(:size, _from, state), do: {:reply, map_size(state.forward), state}

  def handle_call(:keys_by_recency, _from, state) do
    keys =
      state.access
      |> Enum.sort_by(fn {_k, tick} -> tick end)
      |> Enum.map(fn {k, _tick} -> k end)

    {:reply, keys, state}
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

Give me only the complete implementation of `init` (including the
`@doc`/`@spec`/`@impl` lines shown above it in the module, if any) — the
function alone, not the whole module.
