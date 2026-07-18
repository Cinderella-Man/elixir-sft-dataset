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
defmodule BoundedBiMap do
  use GenServer

  ## Client API

  def start_link(opts) do
    {name, opts} = Keyword.pop(opts, :name)
    {capacity, opts} = Keyword.pop(opts, :capacity)
    GenServer.start_link(__MODULE__, capacity, [name: name] ++ opts)
  end

  def put(name, key, value), do: GenServer.call(name, {:put, key, value})

  def get_by_key(name, key), do: GenServer.call(name, {:get_by_key, key})

  def get_by_value(name, value), do: GenServer.call(name, {:get_by_value, value})

  def delete(name, key), do: GenServer.call(name, {:delete, key})

  def size(name), do: GenServer.call(name, :size)

  def keys_by_recency(name), do: GenServer.call(name, :keys_by_recency)

  ## Server callbacks

  @impl true
  def init(capacity) when is_integer(capacity) and capacity > 0 do
    {:ok, %{forward: %{}, reverse: %{}, access: %{}, clock: 0, capacity: capacity}}
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
