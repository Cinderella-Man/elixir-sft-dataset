# Fill in the middle: `touch/2`

Implement the private `touch/2` helper. It takes the current server `state` and a
`key` that was just used (by a `put` or a successful `get_by_key`/`get_by_value`)
and returns an updated state that refreshes that key's recency. To do this, write
the current `clock` value as the key's new tick in the `access` map (replacing any
previous tick for that key), and advance `clock` by 1 so the next use gets a
strictly larger tick. The `forward` and `reverse` maps must be left unchanged; only
`access` and `clock` change. Return the updated state map.

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
    # TODO
  end

  defp evict_lru(f, r, a) do
    {lru_key, _tick} = Enum.min_by(a, fn {_k, tick} -> tick end)
    value = Map.fetch!(f, lru_key)
    {Map.delete(f, lru_key), Map.delete(r, value), Map.delete(a, lru_key)}
  end
end
```