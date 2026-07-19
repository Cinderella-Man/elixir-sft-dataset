# Write the missing @spec

Below is a complete, working module — except that the `@spec` for
`get_by_key/2` has been removed; its place is marked `# TODO: @spec`.
Write exactly that typespec: one `@spec` attribute for `get_by_key/2`,
consistent with the function's arguments, guards, and every return shape
the implementation can produce. Change nothing else.

## The module with the `@spec` for `get_by_key/2` missing

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
  # TODO: @spec
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

Give me only the `@spec` attribute — the attribute alone (however many
lines it spans), not the whole module.
