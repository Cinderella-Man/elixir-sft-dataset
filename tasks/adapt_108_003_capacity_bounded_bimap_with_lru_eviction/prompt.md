# Adapt existing code to a new specification

Below is a complete, working, tested Elixir solution to a related task. Do not
start from scratch: treat it as the codebase you have been asked to change.
Modify it to satisfy the new specification that follows — keep whatever carries
over, and change, add, or remove whatever the new specification requires.

Where the existing code and the new specification disagree (module name, public
API, behavior, constraints, output format), the new specification wins. Give me
the complete final result.

## Existing code (your starting point)

```elixir
defmodule BiMap do
  @moduledoc """
  A GenServer maintaining a bidirectional (bijective) mapping between keys and
  values.

  Every key maps to exactly one value and every value maps back to exactly one
  key. The bijection invariant is enforced on every `put/3`: reassigning a key
  orphans its old value, and reassigning a value orphans its old key, so the
  forward and reverse maps stay perfectly consistent.

  Keys and values may be any term.
  """

  use GenServer

  ## Client API

  @doc """
  Starts the BiMap process.

  Accepts a `:name` option used to register the process. All other functions
  accept that name (or any valid GenServer server reference) as their first
  argument.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    {name, opts} = Keyword.pop(opts, :name)
    GenServer.start_link(__MODULE__, :ok, [name: name] ++ opts)
  end

  @doc """
  Inserts or updates the association between `key` and `value`, preserving the
  bijection invariant. Always returns `:ok`.
  """
  @spec put(GenServer.server(), term(), term()) :: :ok
  def put(name, key, value) do
    GenServer.call(name, {:put, key, value})
  end

  @doc """
  Returns `{:ok, value}` if `key` is present, otherwise `:error`.
  """
  @spec get_by_key(GenServer.server(), term()) :: {:ok, term()} | :error
  def get_by_key(name, key) do
    GenServer.call(name, {:get_by_key, key})
  end

  @doc """
  Returns `{:ok, key}` if `value` is present, otherwise `:error`.
  """
  @spec get_by_value(GenServer.server(), term()) :: {:ok, term()} | :error
  def get_by_value(name, value) do
    GenServer.call(name, {:get_by_value, value})
  end

  @doc """
  Removes `key` and its associated value in both directions. Always returns
  `:ok`, even when `key` is absent.
  """
  @spec delete(GenServer.server(), term()) :: :ok
  def delete(name, key) do
    GenServer.call(name, {:delete, key})
  end

  ## Server callbacks

  @impl true
  def init(:ok) do
    # forward: key => value, reverse: value => key
    {:ok, %{forward: %{}, reverse: %{}}}
  end

  @impl true
  def handle_call({:put, key, value}, _from, state) do
    %{forward: forward, reverse: reverse} = state

    # If key currently points to a different value, orphan that old value.
    reverse =
      case Map.fetch(forward, key) do
        {:ok, ^value} -> reverse
        {:ok, old_value} -> Map.delete(reverse, old_value)
        :error -> reverse
      end

    # If value currently points to a different key, orphan that old key.
    forward =
      case Map.fetch(reverse, value) do
        {:ok, ^key} -> forward
        {:ok, old_key} -> Map.delete(forward, old_key)
        :error -> forward
      end

    forward = Map.put(forward, key, value)
    reverse = Map.put(reverse, value, key)

    {:reply, :ok, %{state | forward: forward, reverse: reverse}}
  end

  @impl true
  def handle_call({:get_by_key, key}, _from, state) do
    {:reply, Map.fetch(state.forward, key), state}
  end

  @impl true
  def handle_call({:get_by_value, value}, _from, state) do
    {:reply, Map.fetch(state.reverse, value), state}
  end

  @impl true
  def handle_call({:delete, key}, _from, state) do
    %{forward: forward, reverse: reverse} = state

    case Map.fetch(forward, key) do
      {:ok, value} ->
        new_state = %{
          state
          | forward: Map.delete(forward, key),
            reverse: Map.delete(reverse, value)
        }

        {:reply, :ok, new_state}

      :error ->
        {:reply, :ok, state}
    end
  end
end
```

## New specification

# Capacity-Bounded BiMap with LRU Eviction

Write me an Elixir GenServer module called `BoundedBiMap` that maintains a **bidirectional mapping** (a bijection between keys and values, exactly like a classic BiMap) but with a **fixed maximum number of pairs** enforced by **least-recently-used (LRU) eviction**. Memory is bounded by construction: once the map is full, inserting a brand-new key evicts the least-recently-used pair to make room.

## Public API

- `BoundedBiMap.start_link(opts)` — starts the process. It must accept a `:name` option used to register the process and a required `:capacity` option (a positive integer, the maximum number of pairs). `start_link` must REFUSE any capacity that is not a positive integer — the guarded `init/1` has no clause for it, so the start fails rather than booting a broken map. All other functions take the name (or any valid GenServer server reference) as their first argument. Return the usual `{:ok, pid}`.

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
