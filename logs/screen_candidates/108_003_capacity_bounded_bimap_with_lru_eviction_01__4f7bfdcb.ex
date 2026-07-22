defmodule BoundedBiMap do
  @moduledoc """
  A capacity-bounded bidirectional map (bijection) with least-recently-used eviction.

  `BoundedBiMap` maintains a one-to-one correspondence between keys and values: every key
  maps to exactly one value and every value maps back to exactly one key. Unlike a classic
  BiMap, this implementation holds at most `:capacity` pairs. Once the map is full, inserting
  a brand-new key evicts the least-recently-used pair, so memory is bounded by construction.

  ## Recency

  A pair is "used" by:

    * `put/3` — inserting or updating the pair;
    * a successful `get_by_key/2` or `get_by_value/2`.

  Using a pair moves it to the most-recently-used end of the recency order, protecting it
  from the next eviction. `keys_by_recency/1` exposes the current order (least-recently-used
  first) for inspection.

  ## Eviction

  Eviction only ever happens when a *brand-new* key must be installed while the map already
  holds `capacity` pairs. Overwriting an existing key's value does not change the pair count
  and therefore never evicts. Bijection maintenance (dropping the old key that owned an
  incoming value) frees a slot and may remove the need to evict at all.

  ## Example

      iex> {:ok, _pid} = BoundedBiMap.start_link(name: :demo, capacity: 2)
      iex> BoundedBiMap.put(:demo, :a, 1)
      :ok
      iex> BoundedBiMap.put(:demo, :b, 2)
      :ok
      iex> BoundedBiMap.get_by_key(:demo, :a)
      {:ok, 1}
      iex> BoundedBiMap.put(:demo, :c, 3)
      :ok
      iex> BoundedBiMap.get_by_key(:demo, :b)
      :error
      iex> BoundedBiMap.get_by_value(:demo, 3)
      {:ok, :c}

  Implementation note: recency is tracked with a monotonically increasing counter plus a
  `:gb_trees` ordered set keyed by that counter, giving O(log n) use/evict operations
  without scanning the whole map.
  """

  use GenServer

  @typedoc "Any term used as a key."
  @type key :: term()

  @typedoc "Any term used as a value."
  @type value :: term()

  @typedoc "A GenServer server reference."
  @type server :: GenServer.server()

  defstruct capacity: 1,
            forward: %{},
            backward: %{},
            recency: nil,
            clock: 0

  @typep t :: %__MODULE__{
           capacity: pos_integer(),
           forward: %{optional(key()) => {value(), non_neg_integer()}},
           backward: %{optional(value()) => key()},
           recency: :gb_trees.tree(non_neg_integer(), key()),
           clock: non_neg_integer()
         }

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  @doc """
  Starts a `BoundedBiMap` process.

  ## Options

    * `:capacity` (required) — a positive integer, the maximum number of pairs held.
    * `:name` — a name used to register the process; any valid `GenServer` name.

  Any other options are passed through to `GenServer.start_link/3`.

  Raises `ArgumentError` if `:capacity` is missing or is not a positive integer.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) when is_list(opts) do
    {capacity, opts} = Keyword.pop(opts, :capacity)

    unless is_integer(capacity) and capacity > 0 do
      raise ArgumentError,
            "BoundedBiMap requires a :capacity option that is a positive integer, " <>
              "got: #{inspect(capacity)}"
    end

    {name, opts} = Keyword.pop(opts, :name)
    server_opts = if is_nil(name), do: opts, else: Keyword.put(opts, :name, name)

    GenServer.start_link(__MODULE__, capacity, server_opts)
  end

  @doc """
  Associates `key` with `value`, preserving the bijection. Always returns `:ok`.

  Bijection maintenance runs first: if `key` already maps to another value, that value's
  reverse mapping is dropped; if `value` already belongs to another key, that key is removed
  entirely (freeing a slot).

  If, after maintenance, `key` is brand new and the map is at capacity, the least-recently-used
  pair is evicted in both directions to make room. Updating an existing key never evicts.

  The pair becomes the most-recently-used one.
  """
  @spec put(server(), key(), value()) :: :ok
  def put(server, key, value) do
    GenServer.call(server, {:put, key, value})
  end

  @doc """
  Looks `key` up, returning `{:ok, value}` when present and `:error` otherwise.

  A successful lookup refreshes the pair's recency, making it the most-recently-used pair.
  """
  @spec get_by_key(server(), key()) :: {:ok, value()} | :error
  def get_by_key(server, key) do
    GenServer.call(server, {:get_by_key, key})
  end

  @doc """
  Looks `value` up in the reverse direction, returning `{:ok, key}` when present and `:error`
  otherwise.

  A successful lookup refreshes the pair's recency, making it the most-recently-used pair.
  """
  @spec get_by_value(server(), value()) :: {:ok, key()} | :error
  def get_by_value(server, value) do
    GenServer.call(server, {:get_by_value, value})
  end

  @doc """
  Removes `key` and its associated value in both directions, freeing a slot.

  Deleting an absent key is a harmless no-op. Always returns `:ok`.
  """
  @spec delete(server(), key()) :: :ok
  def delete(server, key) do
    GenServer.call(server, {:delete, key})
  end

  @doc """
  Returns the current number of pairs held, which never exceeds the configured capacity.
  """
  @spec size(server()) :: non_neg_integer()
  def size(server) do
    GenServer.call(server, :size)
  end

  @doc """
  Returns the current keys ordered least-recently-used first and most-recently-used last.

  The head of the list is the next pair that would be evicted by a brand-new-key insertion at
  capacity.
  """
  @spec keys_by_recency(server()) :: [key()]
  def keys_by_recency(server) do
    GenServer.call(server, :keys_by_recency)
  end

  # ---------------------------------------------------------------------------
  # GenServer callbacks
  # ---------------------------------------------------------------------------

  @impl GenServer
  def init(capacity) do
    {:ok, %__MODULE__{capacity: capacity, recency: :gb_trees.empty()}}
  end

  @impl GenServer
  def handle_call({:put, key, value}, _from, state) do
    {:reply, :ok, do_put(state, key, value)}
  end

  def handle_call({:get_by_key, key}, _from, state) do
    case Map.fetch(state.forward, key) do
      {:ok, {value, stamp}} ->
        {:reply, {:ok, value}, touch(state, key, stamp)}

      :error ->
        {:reply, :error, state}
    end
  end

  def handle_call({:get_by_value, value}, _from, state) do
    case Map.fetch(state.backward, value) do
      {:ok, key} ->
        {_value, stamp} = Map.fetch!(state.forward, key)
        {:reply, {:ok, key}, touch(state, key, stamp)}

      :error ->
        {:reply, :error, state}
    end
  end

  def handle_call({:delete, key}, _from, state) do
    {:reply, :ok, drop_key(state, key)}
  end

  def handle_call(:size, _from, state) do
    {:reply, map_size(state.forward), state}
  end

  def handle_call(:keys_by_recency, _from, state) do
    keys = for {_stamp, key} <- :gb_trees.to_list(state.recency), do: key
    {:reply, keys, state}
  end

  # ---------------------------------------------------------------------------
  # Internals
  # ---------------------------------------------------------------------------

  @spec do_put(t(), key(), value()) :: t()
  defp do_put(state, key, value) do
    state
    |> unlink_old_value(key)
    |> drop_conflicting_key(key, value)
    |> evict_if_needed(key)
    |> install(key, value)
  end

  # If `key` already holds a different value, that value loses its reverse mapping.
  @spec unlink_old_value(t(), key()) :: t()
  defp unlink_old_value(state, key) do
    case Map.fetch(state.forward, key) do
      {:ok, {old_value, _stamp}} -> %{state | backward: Map.delete(state.backward, old_value)}
      :error -> state
    end
  end

  # If `value` already belongs to a different key, that key is removed entirely.
  @spec drop_conflicting_key(t(), key(), value()) :: t()
  defp drop_conflicting_key(state, key, value) do
    case Map.fetch(state.backward, value) do
      {:ok, other_key} when other_key != key -> drop_key(state, other_key)
      _other -> state
    end
  end

  # Only a brand-new key at capacity forces an eviction.
  @spec evict_if_needed(t(), key()) :: t()
  defp evict_if_needed(state, key) do
    brand_new? = not Map.has_key?(state.forward, key)

    if brand_new? and map_size(state.forward) >= state.capacity do
      evict_lru(state)
    else
      state
    end
  end

  @spec evict_lru(t()) :: t()
  defp evict_lru(state) do
    case :gb_trees.is_empty(state.recency) do
      true ->
        state

      false ->
        {_stamp, lru_key, recency} = :gb_trees.take_smallest(state.recency)
        {{old_value, _stamp}, forward} = Map.pop!(state.forward, lru_key)

        %{
          state
          | forward: forward,
            backward: Map.delete(state.backward, old_value),
            recency: recency
        }
    end
  end

  @spec install(t(), key(), value()) :: t()
  defp install(state, key, value) do
    recency =
      case Map.fetch(state.forward, key) do
        {:ok, {_old_value, stamp}} -> :gb_trees.delete(stamp, state.recency)
        :error -> state.recency
      end

    stamp = state.clock

    %{
      state
      | forward: Map.put(state.forward, key, {value, stamp}),
        backward: Map.put(state.backward, value, key),
        recency: :gb_trees.insert(stamp, key, recency),
        clock: state.clock + 1
    }
  end

  # Moves an existing key to the most-recently-used end.
  @spec touch(t(), key(), non_neg_integer()) :: t()
  defp touch(state, key, stamp) do
    new_stamp = state.clock

    recency =
      state.recency
      |> :gb_trees.delete(stamp)
      |> then(&:gb_trees.insert(new_stamp, key, &1))

    forward = Map.update!(state.forward, key, fn {value, _old} -> {value, new_stamp} end)

    %{state | forward: forward, recency: recency, clock: state.clock + 1}
  end

  @spec drop_key(t(), key()) :: t()
  defp drop_key(state, key) do
    case Map.pop(state.forward, key) do
      {nil, _forward} ->
        state

      {{value, stamp}, forward} ->
        %{
          state
          | forward: forward,
            backward: Map.delete(state.backward, value),
            recency: :gb_trees.delete(stamp, state.recency)
        }
    end
  end
end