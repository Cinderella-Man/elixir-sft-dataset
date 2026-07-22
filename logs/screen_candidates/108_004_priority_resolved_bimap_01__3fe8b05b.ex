defmodule PriorityBiMap do
  @moduledoc """
  A `GenServer` maintaining a bidirectional map (a bijection between keys and values) where
  every pair carries an integer priority and collisions are resolved by priority instead of
  last-write-wins.

  A classic BiMap evicts whatever collides with a new `put`. Here, a `put` that collides with
  one or more existing pairs is accepted **only** when its priority is strictly greater than
  the priority of every conflicting pair. Otherwise the write is rejected and the structure is
  left completely untouched.

  A single `put/4` can conflict with at most two existing pairs:

    * the pair currently stored at `key`, when `key` maps to a different value, and
    * the pair currently stored at `value`, when `value` maps to a different key.

  When the new pair wins, both conflicting pairs are evicted so that the bijection is
  preserved, and the displaced `{key, value}` pairs are reported to the caller.

  ## Invariants

    * The structure is always a true bijection: `get_by_key(name, k) == {:ok, v}` if and only
      if `get_by_value(name, v) == {:ok, k}`.
    * A rejected `put` is a complete no-op: no mapping and no priority is added, removed or
      changed.
    * An accepted conflicting `put` evicts exactly the conflicting pairs and reports them.

  ## Example

      {:ok, _pid} = PriorityBiMap.start_link(name: :bimap)
      {:ok, []} = PriorityBiMap.put(:bimap, :a, 1, 5)
      {:error, :rejected} = PriorityBiMap.put(:bimap, :b, 1, 5)
      {:ok, [{:a, 1}]} = PriorityBiMap.put(:bimap, :b, 1, 6)
      :error = PriorityBiMap.get_by_key(:bimap, :a)
      {:ok, :b} = PriorityBiMap.get_by_value(:bimap, 1)

  """

  use GenServer

  @typedoc "A key stored in the bimap. Any term."
  @type key :: term()

  @typedoc "A value stored in the bimap. Any term."
  @type value :: term()

  @typedoc "The priority attached to a `{key, value}` pair."
  @type priority :: integer()

  @typedoc "A displaced association reported by an accepted `put/4`."
  @type pair :: {key(), value()}

  defmodule State do
    @moduledoc false

    defstruct forward: %{}, backward: %{}, priorities: %{}

    @type t :: %__MODULE__{
            forward: %{optional(term()) => term()},
            backward: %{optional(term()) => term()},
            priorities: %{optional(term()) => integer()}
          }
  end

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  @doc """
  Starts a `PriorityBiMap` process.

  Accepts the usual `GenServer` options; in particular `:name`, which registers the process
  under that name so it can be used as the first argument of the other functions.

  Returns `{:ok, pid}` on success.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    {name, opts} = Keyword.pop(opts, :name)
    server_opts = if name, do: [name: name], else: []
    GenServer.start_link(__MODULE__, opts, server_opts)
  end

  @doc """
  Attempts to install the association `{key, value}` with the given `priority`.

  Resolution rules:

    * if `key` already maps to exactly `value`, the pair is kept and its stored priority is
      updated to `priority`; returns `{:ok, []}`;
    * if neither `key` nor `value` is present, the pair is installed; returns `{:ok, []}`;
    * if the write conflicts with one or two existing pairs, it is accepted only when
      `priority` is strictly greater than every conflicting pair's priority. On acceptance all
      conflicting pairs are evicted and the new pair installed, returning `{:ok, evicted}`
      where `evicted` is the list of displaced `{key, value}` pairs. Otherwise (including
      ties) nothing changes and `{:error, :rejected}` is returned.
  """
  @spec put(GenServer.server(), key(), value(), priority()) ::
          {:ok, [pair()]} | {:error, :rejected}
  def put(server, key, value, priority) when is_integer(priority) do
    GenServer.call(server, {:put, key, value, priority})
  end

  @doc """
  Returns `{:ok, value}` when `key` is present in the bimap, `:error` otherwise.
  """
  @spec get_by_key(GenServer.server(), key()) :: {:ok, value()} | :error
  def get_by_key(server, key) do
    GenServer.call(server, {:get_by_key, key})
  end

  @doc """
  Returns `{:ok, key}` when `value` is present in the bimap, `:error` otherwise.
  """
  @spec get_by_value(GenServer.server(), value()) :: {:ok, key()} | :error
  def get_by_value(server, value) do
    GenServer.call(server, {:get_by_value, value})
  end

  @doc """
  Returns `{:ok, priority}` for the pair stored at `key`, or `:error` when `key` is absent.
  """
  @spec priority(GenServer.server(), key()) :: {:ok, priority()} | :error
  def priority(server, key) do
    GenServer.call(server, {:priority, key})
  end

  @doc """
  Removes `key`, its associated value and its priority from the bimap.

  Always returns `:ok`; deleting an absent key is a harmless no-op.
  """
  @spec delete(GenServer.server(), key()) :: :ok
  def delete(server, key) do
    GenServer.call(server, {:delete, key})
  end

  # ---------------------------------------------------------------------------
  # GenServer callbacks
  # ---------------------------------------------------------------------------

  @impl GenServer
  def init(_opts) do
    {:ok, %State{}}
  end

  @impl GenServer
  def handle_call({:put, key, value, priority}, _from, state) do
    case resolve(state, key, value, priority) do
      {:ok, evicted} ->
        {:reply, {:ok, evicted}, install(state, key, value, priority, evicted)}

      {:error, :rejected} ->
        {:reply, {:error, :rejected}, state}
    end
  end

  def handle_call({:get_by_key, key}, _from, state) do
    {:reply, Map.fetch(state.forward, key), state}
  end

  def handle_call({:get_by_value, value}, _from, state) do
    {:reply, Map.fetch(state.backward, value), state}
  end

  def handle_call({:priority, key}, _from, state) do
    {:reply, Map.fetch(state.priorities, key), state}
  end

  def handle_call({:delete, key}, _from, state) do
    {:reply, :ok, drop_key(state, key)}
  end

  # ---------------------------------------------------------------------------
  # Internal helpers
  # ---------------------------------------------------------------------------

  # Decides whether the incoming pair wins, and if so which pairs it displaces.
  @spec resolve(State.t(), key(), value(), priority()) :: {:ok, [pair()]} | {:error, :rejected}
  defp resolve(state, key, value, priority) do
    conflicts = conflicts(state, key, value)

    cond do
      same_pair?(state, key, value) -> {:ok, []}
      conflicts == [] -> {:ok, []}
      Enum.all?(conflicts, fn {_k, _v, p} -> priority > p end) -> {:ok, pairs(conflicts)}
      true -> {:error, :rejected}
    end
  end

  # The pair already stored exactly as `{key, value}`.
  @spec same_pair?(State.t(), key(), value()) :: boolean()
  defp same_pair?(state, key, value) do
    Map.fetch(state.forward, key) == {:ok, value}
  end

  # Existing pairs that collide with `{key, value}`, as `{key, value, priority}` triples.
  # At most two: the key-side pair and the value-side pair (deduplicated when identical).
  @spec conflicts(State.t(), key(), value()) :: [{key(), value(), priority()}]
  defp conflicts(state, key, value) do
    key_side =
      case Map.fetch(state.forward, key) do
        {:ok, ^value} -> nil
        {:ok, other_value} -> {key, other_value, Map.fetch!(state.priorities, key)}
        :error -> nil
      end

    value_side =
      case Map.fetch(state.backward, value) do
        {:ok, ^key} -> nil
        {:ok, other_key} -> {other_key, value, Map.fetch!(state.priorities, other_key)}
        :error -> nil
      end

    [key_side, value_side]
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
  end

  @spec pairs([{key(), value(), priority()}]) :: [pair()]
  defp pairs(conflicts), do: Enum.map(conflicts, fn {k, v, _p} -> {k, v} end)

  # Evicts every displaced pair, then installs the winning pair.
  @spec install(State.t(), key(), value(), priority(), [pair()]) :: State.t()
  defp install(state, key, value, priority, evicted) do
    state = Enum.reduce(evicted, state, fn {k, _v}, acc -> drop_key(acc, k) end)

    %State{
      state
      | forward: Map.put(state.forward, key, value),
        backward: Map.put(state.backward, value, key),
        priorities: Map.put(state.priorities, key, priority)
    }
  end

  # Removes `key`, its partner and its priority. No-op when `key` is absent.
  @spec drop_key(State.t(), key()) :: State.t()
  defp drop_key(state, key) do
    case Map.fetch(state.forward, key) do
      {:ok, value} ->
        %State{
          state
          | forward: Map.delete(state.forward, key),
            backward: Map.delete(state.backward, value),
            priorities: Map.delete(state.priorities, key)
        }

      :error ->
        state
    end
  end
end