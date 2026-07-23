# Migrate existing code to a new spec

Starting point: the working, tested solution below, from a related task.
Change it — no ground-up rewrite — until it satisfies the specification
that follows. On any disagreement between the two (module name, public API,
behavior, constraints, output format), the new specification wins. Output
the complete updated code.

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

# Bidirectional Multimap (Many-to-Many) GenServer

Write me an Elixir GenServer module called `BiMultiMap` that maintains a **bidirectional many-to-many relation** between keys and values. Unlike a strict bijection, a single key may be associated with *many* values, and a single value may be associated with *many* keys. What must always hold is that the forward and reverse indexes agree perfectly: an association `key ↔ value` is either present in both directions or absent from both.

## Public API

- `BiMultiMap.start_link(opts)` — starts the process. It must accept a `:name` option used to register the process (all other functions take that name — or any valid GenServer server reference — as their first argument). Return the usual `{:ok, pid}`.

- `BiMultiMap.put(name, key, value)` — records the association between `key` and `value`. Always returns `:ok`. Adding the same `{key, value}` pair again is an idempotent no-op (the relation is a *set* of pairs, never a multiset). A key may accumulate several values and a value may accumulate several keys.

- `BiMultiMap.member?(name, key, value)` — returns `true` if the association `{key, value}` is currently present, otherwise `false`.

- `BiMultiMap.get_by_key(name, key)` — returns a `MapSet` of all values currently associated with `key` (an **empty `MapSet`** if the key has none).

- `BiMultiMap.get_by_value(name, value)` — returns a `MapSet` of all keys currently associated with `value` (an **empty `MapSet`** if the value has none).

- `BiMultiMap.delete(name, key, value)` — removes the single association `{key, value}` in both directions. Returns `:ok`. Removing an association that isn't present is a harmless no-op.

- `BiMultiMap.delete_key(name, key)` — removes `key` and *all* of its associations, cleaning up the reverse index for every value that was attached to it. Returns `:ok`.

- `BiMultiMap.delete_value(name, value)` — removes `value` and *all* of its associations, cleaning up the forward index for every key that was attached to it. Returns `:ok`.

## The invariant

At all times the forward and reverse indexes must stay consistent:

- `member?(name, k, v)` is `true` **iff** `v` is in `get_by_key(name, k)` **iff** `k` is in `get_by_value(name, v)`.
- When the last value is removed from a key (via `delete/3`, `delete_value/2`, etc.), that key must disappear entirely from the forward index — `get_by_key` returns an empty `MapSet` and the internal map no longer holds a stale empty set. The symmetric rule holds for values in the reverse index.

Keys and values can be any term (atoms, integers, strings, tuples, etc.).

Give me the complete module in a single file. Use only the OTP standard library — no external dependencies.
