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
defmodule BiMap do
  use GenServer

  ## Client API

  def start_link(opts) do
    {name, opts} = Keyword.pop(opts, :name)
    GenServer.start_link(__MODULE__, :ok, [name: name] ++ opts)
  end

  def put(name, key, value) do
    GenServer.call(name, {:put, key, value})
  end

  def get_by_key(name, key) do
    GenServer.call(name, {:get_by_key, key})
  end

  def get_by_value(name, value) do
    GenServer.call(name, {:get_by_value, value})
  end

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
