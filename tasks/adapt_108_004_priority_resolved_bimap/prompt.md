# Rework this solution for a changed brief

The module below is a complete, tested solution to a neighboring task. Treat
it as your starting codebase, not as a suggestion — carry over what still
fits and rewrite what the new brief demands. Where old code and the new
specification conflict (module name, public API, behavior, constraints,
output format), the new specification is authoritative. Return the complete
final result.

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

# Priority-Resolved BiMap

Write me an Elixir GenServer module called `PriorityBiMap` that maintains a **bidirectional mapping** (a bijection between keys and values) where every pair carries a **priority**, and conflicts are resolved by priority rather than by last-write-wins. Unlike a classic BiMap — where a new `put` always evicts whatever collides with it — here a lower-priority write is **rejected** and leaves the existing mappings untouched.

## Public API

- `PriorityBiMap.start_link(opts)` — starts the process. It must accept a `:name` option used to register the process (all other functions take that name — or any valid GenServer server reference — as their first argument). Return the usual `{:ok, pid}`.

- `PriorityBiMap.put(name, key, value, priority)` — attempts to install the association `{key, value}` with the given integer `priority`. A `put` can conflict with **up to two** existing pairs: the pair currently at `key` (if `key` maps to a *different* value) and the pair currently at `value` (if `value` maps to a *different* key). Resolution:
  - **Same pair already present** (`key` already maps to exactly `value`): accept and update the stored priority to `priority`. Returns `{:ok, []}` (nothing displaced).
  - **No conflict** (both `key` and `value` are free): install the pair. Returns `{:ok, []}`.
  - **Conflict(s) exist**: the new pair is accepted **only if `priority` is strictly greater than every conflicting pair's priority**. On acceptance, all conflicting pairs are evicted and the new pair installed; returns `{:ok, evicted}` where `evicted` is the list of displaced `{key, value}` pairs. If `priority` is **not** strictly greater than some conflicting pair (including ties), the put is **rejected**: nothing changes and it returns `{:error, :rejected}`.

- `PriorityBiMap.get_by_key(name, key)` — returns `{:ok, value}` if `key` is present, otherwise `:error`.

- `PriorityBiMap.get_by_value(name, value)` — returns `{:ok, key}` if `value` is present, otherwise `:error`.

- `PriorityBiMap.priority(name, key)` — returns `{:ok, priority}` for the pair at `key`, otherwise `:error`.

- `PriorityBiMap.delete(name, key)` — removes `key` and its associated value (both directions), including its priority. Returns `:ok`. Deleting an absent key is a harmless no-op.

## The invariant

- The structure is always a true bijection: every `get_by_key(name, k)` returning `{:ok, v}` implies `get_by_value(name, v)` returns `{:ok, k}`, and vice versa; each key/value is associated with at most one partner.
- A rejected `put` is a complete no-op: no mapping, no priority, no partial change.
- An accepted conflicting `put` evicts every conflicting pair (both the key-side and the value-side pair when they differ) so the bijection is preserved, and reports exactly those displaced pairs.

Keys and values can be any term (priorities are integers). Use only the OTP standard library — no external dependencies. Give me the complete module in a single file.
