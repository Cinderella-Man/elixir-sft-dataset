# Implement the missing function

Below you'll find a task's full specification, then a working, tested
solution with one gap: `init` — every clause body swapped for
`# TODO`. Rebuild exactly that function so the module passes the task's
whole suite again, and leave every other line precisely as shown.

## The task

# Bidirectional Map GenServer

Write me an Elixir GenServer module called `BiMap` that maintains a **bidirectional mapping** between keys and values. Every key maps to exactly one value, and every value maps back to exactly one key — the mapping is always a bijection.

## Public API

- `BiMap.start_link(opts)` — starts the process. It must accept a `:name` option used to register the process (all other functions take that name — or any valid GenServer server reference — as their first argument). Return the usual `{:ok, pid}`.

- `BiMap.put(name, key, value)` — inserts or updates the association between `key` and `value`. Always returns `:ok`. This is where the bijection invariant must be enforced:
  - If `key` is already associated with a *different* value, the old value's reverse mapping must be removed before the new one is installed.
  - If `value` is already associated with a *different* key, that old key's mapping must be removed (so the value now points to the new key).
  - Putting the exact same `{key, value}` pair again is a no-op that leaves the pair intact.

- `BiMap.get_by_key(name, key)` — returns `{:ok, value}` if `key` is present, otherwise `:error`.

- `BiMap.get_by_value(name, value)` — returns `{:ok, key}` if `value` is present, otherwise `:error`.

- `BiMap.delete(name, key)` — removes `key` and its associated value (both directions). Returns `:ok`. Deleting a key that isn't present is a harmless no-op that still returns `:ok`.

## The invariant

At all times the structure must remain a true bijection: there is never a forward entry `key → value` without the matching reverse entry `value → key`, and no value or key is ever associated with more than one partner. Concretely, after any sequence of `put`/`delete` calls:

- Every `get_by_key(name, k)` that returns `{:ok, v}` implies `get_by_value(name, v)` returns `{:ok, k}`, and vice versa.
- Reassigning a key to a new value must orphan the old value (its `get_by_value` becomes `:error`).
- Reassigning a value to a new key must orphan the old key (its `get_by_key` becomes `:error`).

Keys and values can be any term (atoms, integers, strings, tuples, etc.).

Give me the complete module in a single file. Use only the OTP standard library — no external dependencies.

## The module with `init` missing

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

  def init(:ok) do
    # TODO
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

Reply with `init` alone (bring along any `@doc`/`@spec`/`@impl` lines
that belong directly above it) — just the function, never the whole
module.
