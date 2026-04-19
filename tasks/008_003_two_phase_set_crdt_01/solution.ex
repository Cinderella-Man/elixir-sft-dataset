defmodule TwoPhaseSet do
  @moduledoc """
  A GenServer implementing a Two-Phase Set (2P-Set) CRDT.

  ## Overview

  A 2P-Set is a Conflict-free Replicated Data Type (CRDT) that supports both
  add and remove operations on set elements. It achieves this by maintaining
  two grow-only sets (G-Sets):

    - `added`   — the set of all elements that have ever been added
    - `removed` — the "tombstone" set of all elements that have been removed

  An element is considered present when it is in `added` but not in `removed`.

  ## Key Constraint

  Once an element is removed, it can **never be re-added**. This permanent
  tombstone is the trade-off that gives the 2P-Set its simplicity: no causal
  metadata (vector clocks, unique tags, etc.) is required.

  ## CRDT Merge Semantics

  Merging two 2P-Set states is performed by computing the **set union** of
  each G-Set independently:

      merged.added   = union(local.added,   remote.added)
      merged.removed = union(local.removed, remote.removed)

  This merge function is:
    - **Idempotent**: `merge(s, s) == s`
    - **Commutative**: `merge(a, b) == merge(b, a)`
    - **Associative**: `merge(merge(a, b), c) == merge(a, merge(b, c))`

  ## Example

      {:ok, s} = TwoPhaseSet.start_link([])

      TwoPhaseSet.add(s, :alice)
      TwoPhaseSet.add(s, :bob)
      TwoPhaseSet.remove(s, :alice)

      TwoPhaseSet.members(s)
      #=> MapSet.new([:bob])

      # :alice can never be re-added
      TwoPhaseSet.add(s, :alice)
      #=> ** (ArgumentError) ...
  """

  use GenServer

  @type element :: term()
  @type tp_state :: %{added: MapSet.t(), removed: MapSet.t()}
  @type server :: GenServer.server()

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  @doc """
  Starts the TwoPhaseSet process.

  ## Options

    * `:name` — optional name for process registration.

  ## Examples

      {:ok, pid} = TwoPhaseSet.start_link([])
      {:ok, _}   = TwoPhaseSet.start_link(name: MySet)
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    {name_opts, _rest} = Keyword.split(opts, [:name])
    GenServer.start_link(__MODULE__, :ok, name_opts)
  end

  @doc """
  Adds `element` to the set.

  Raises `ArgumentError` if the element has previously been removed (tombstoned).
  Adding an element that is already present is a no-op.

  Returns `:ok`.
  """
  @spec add(server(), element()) :: :ok
  def add(server, element) do
    case GenServer.call(server, {:add, element}) do
      :ok ->
        :ok

      {:error, :tombstoned} ->
        raise ArgumentError,
              "cannot re-add element #{inspect(element)}: it has been permanently removed from the 2P-Set"
    end
  end

  @doc """
  Removes `element` from the set.

  The element must be currently present (added and not yet removed). Raises
  `ArgumentError` if the element is not a current member.

  Returns `:ok`.
  """
  @spec remove(server(), element()) :: :ok
  def remove(server, element) do
    case GenServer.call(server, {:remove, element}) do
      :ok ->
        :ok

      {:error, :not_a_member} ->
        raise ArgumentError,
              "cannot remove element #{inspect(element)}: it is not a current member of the 2P-Set"
    end
  end

  @doc """
  Returns `true` if `element` is currently in the set, `false` otherwise.

  An element is present when it is in the add-set but not the remove-set.
  """
  @spec member?(server(), element()) :: boolean()
  def member?(server, element) do
    GenServer.call(server, {:member?, element})
  end

  @doc """
  Returns a `MapSet` of all elements currently in the set.
  """
  @spec members(server()) :: MapSet.t()
  def members(server) do
    GenServer.call(server, :members)
  end

  @doc """
  Merges a remote 2P-Set state into the local state.

  `remote_state` must be a map of the form `%{added: MapSet, removed: MapSet}`.

  The merge computes the union of the add-sets and separately the union of the
  remove-sets. This ensures the merge is idempotent, commutative, and associative.

  Returns `:ok`.
  """
  @spec merge(server(), tp_state()) :: :ok
  def merge(server, %{added: added, removed: removed} = _remote_state) do
    GenServer.call(server, {:merge, %{added: MapSet.new(added), removed: MapSet.new(removed)}})
  end

  def merge(_server, invalid) do
    raise ArgumentError,
          "remote_state must be a map with :added and :removed keys, got: #{inspect(invalid)}"
  end

  @doc """
  Returns the raw internal state of the set.

  The returned map has the form:

      %{
        added:   MapSet of all elements ever added,
        removed: MapSet of all elements ever removed (tombstones)
      }

  This value can be sent to a remote node and passed to `TwoPhaseSet.merge/2`.
  """
  @spec state(server()) :: tp_state()
  def state(server) do
    GenServer.call(server, :state)
  end

  # ---------------------------------------------------------------------------
  # GenServer callbacks
  # ---------------------------------------------------------------------------

  @impl GenServer
  def init(:ok) do
    {:ok, empty_state()}
  end

  @impl GenServer
  def handle_call({:add, element}, _from, %{added: added, removed: removed} = state) do
    if MapSet.member?(removed, element) do
      {:reply, {:error, :tombstoned}, state}
    else
      {:reply, :ok, %{state | added: MapSet.put(added, element)}}
    end
  end

  def handle_call({:remove, element}, _from, %{added: added, removed: removed} = state) do
    if MapSet.member?(added, element) and not MapSet.member?(removed, element) do
      {:reply, :ok, %{state | removed: MapSet.put(removed, element)}}
    else
      {:reply, {:error, :not_a_member}, state}
    end
  end

  def handle_call({:member?, element}, _from, state) do
    {:reply, element_present?(state, element), state}
  end

  def handle_call(:members, _from, state) do
    {:reply, compute_members(state), state}
  end

  def handle_call({:merge, remote}, _from, local) do
    {:reply, :ok, merge_states(local, remote)}
  end

  def handle_call(:state, _from, state) do
    {:reply, state, state}
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  @spec empty_state() :: tp_state()
  defp empty_state, do: %{added: MapSet.new(), removed: MapSet.new()}

  @spec element_present?(tp_state(), element()) :: boolean()
  defp element_present?(%{added: added, removed: removed}, element) do
    MapSet.member?(added, element) and not MapSet.member?(removed, element)
  end

  @spec compute_members(tp_state()) :: MapSet.t()
  defp compute_members(%{added: added, removed: removed}) do
    MapSet.difference(added, removed)
  end

  @spec merge_states(tp_state(), tp_state()) :: tp_state()
  defp merge_states(%{added: la, removed: lr}, %{added: ra, removed: rr}) do
    %{
      added: MapSet.union(la, ra),
      removed: MapSet.union(lr, rr)
    }
  end
end
