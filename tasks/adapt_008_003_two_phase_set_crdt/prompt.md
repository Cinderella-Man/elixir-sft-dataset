# Migrate existing code to a new spec

Starting point: the working, tested solution below, from a related task.
Change it — no ground-up rewrite — until it satisfies the specification
that follows. On any disagreement between the two (module name, public API,
behavior, constraints, output format), the new specification wins. Output
the complete updated code.

## Existing code (your starting point)

```elixir
defmodule Counter do
  @moduledoc """
  A GenServer implementing a PN-Counter (Positive-Negative Counter) CRDT.

  ## Overview

  A PN-Counter is a Conflict-free Replicated Data Type (CRDT) that supports
  both increment and decrement operations in distributed systems where nodes
  may not be in constant communication.

  It works by maintaining two grow-only counters (G-Counters):
    - `p` — tracks all increments per node
    - `n` — tracks all decrements per node

  The observable value is `sum(p) - sum(n)`.

  ## CRDT Merge Semantics

  Merging two PN-Counter states is performed by taking the **per-node maximum**
  of each G-Counter independently:

      merged.p[node] = max(local.p[node], remote.p[node])
      merged.n[node] = max(local.n[node], remote.n[node])

  This merge function is:
    - **Idempotent**: `merge(s, s) == s`
    - **Commutative**: `merge(a, b) == merge(b, a)`
    - **Associative**: `merge(merge(a, b), c) == merge(a, merge(b, c))`

  ## Example

      {:ok, s} = Counter.start_link([])

      Counter.increment(s, :node_a, 5)
      Counter.increment(s, :node_b, 3)
      Counter.decrement(s, :node_a, 2)

      Counter.value(s)
      #=> 6  (i.e. (5 + 3) - 2)

      remote = %{p: %{node_c: 10}, n: %{node_c: 4}}
      Counter.merge(s, remote)

      Counter.value(s)
      #=> 12  (i.e. (5 + 3 + 10) - (2 + 4))
  """

  use GenServer

  @type node_id :: term()
  @type amount :: pos_integer()
  @type g_counter :: %{optional(node_id()) => non_neg_integer()}
  @type pn_state :: %{p: g_counter(), n: g_counter()}
  @type server :: GenServer.server()

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  @doc """
  Starts the Counter process.

  ## Options

    * `:name` — optional name for process registration, passed directly to
      `GenServer.start_link/3`. Accepts any valid `GenServer` name term
      (atom, `{:global, term}`, `{:via, module, term}`, etc.).

  ## Examples

      # Anonymous process
      {:ok, pid} = Counter.start_link([])

      # Named process
      {:ok, _} = Counter.start_link(name: MyCounter)
      Counter.value(MyCounter)
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    {name_opts, _rest} =
      Keyword.split(opts, [:name])

    GenServer.start_link(__MODULE__, :ok, name_opts)
  end

  @doc """
  Increments the counter for `node_id` by `amount` (default `1`).

  `amount` must be a positive integer; raises `ArgumentError` otherwise.

  Returns `:ok`.
  """
  @spec increment(server(), node_id(), amount()) :: :ok
  def increment(server, node_id, amount \\ 1) do
    validate_amount!(amount, :increment)
    GenServer.call(server, {:increment, node_id, amount})
  end

  @doc """
  Decrements the counter for `node_id` by `amount` (default `1`).

  `amount` must be a positive integer; raises `ArgumentError` otherwise.

  Returns `:ok`.
  """
  @spec decrement(server(), node_id(), amount()) :: :ok
  def decrement(server, node_id, amount \\ 1) do
    validate_amount!(amount, :decrement)
    GenServer.call(server, {:decrement, node_id, amount})
  end

  @doc """
  Returns the current integer value of the counter.

  Computed as `sum(p values) - sum(n values)` across all nodes.
  """
  @spec value(server()) :: integer()
  def value(server) do
    GenServer.call(server, :value)
  end

  @doc """
  Merges a remote PN-Counter state into the local state.

  `remote_state` must be a map of the form `%{p: %{...}, n: %{...}}` —
  i.e. the structure returned by `Counter.state/1`.

  For each node, the merge takes the **maximum** of the local and remote
  values for both `p` and `n` independently. This ensures the merge is
  idempotent, commutative, and associative.

  Returns `:ok`.
  """
  @spec merge(server(), pn_state()) :: :ok
  def merge(server, %{p: p, n: n} = _remote_state)
      when is_map(p) and is_map(n) do
    GenServer.call(server, {:merge, %{p: p, n: n}})
  end

  def merge(_server, invalid) do
    raise ArgumentError,
          "remote_state must be a map with :p and :n keys, got: #{inspect(invalid)}"
  end

  @doc """
  Returns the raw internal state of the counter.

  The returned map has the form:

      %{
        p: %{node_id => total_increments, ...},
        n: %{node_id => total_decrements, ...}
      }

  This value can be sent to a remote node and passed to `Counter.merge/2`
  to synchronise state.
  """
  @spec state(server()) :: pn_state()
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
  def handle_call({:increment, node_id, amount}, _from, state) do
    new_state = update_in(state, [:p, node_id], fn current -> (current || 0) + amount end)
    {:reply, :ok, new_state}
  end

  def handle_call({:decrement, node_id, amount}, _from, state) do
    new_state = update_in(state, [:n, node_id], fn current -> (current || 0) + amount end)
    {:reply, :ok, new_state}
  end

  def handle_call(:value, _from, state) do
    {:reply, compute_value(state), state}
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

  @spec empty_state() :: pn_state()
  defp empty_state, do: %{p: %{}, n: %{}}

  @spec compute_value(pn_state()) :: integer()
  defp compute_value(%{p: p, n: n}) do
    sum_map(p) - sum_map(n)
  end

  @spec sum_map(g_counter()) :: non_neg_integer()
  defp sum_map(map), do: Enum.reduce(map, 0, fn {_k, v}, acc -> acc + v end)

  @spec merge_states(pn_state(), pn_state()) :: pn_state()
  defp merge_states(%{p: lp, n: ln}, %{p: rp, n: rn}) do
    %{
      p: merge_g_counters(lp, rp),
      n: merge_g_counters(ln, rn)
    }
  end

  # Merges two G-Counters by taking the per-node maximum.
  @spec merge_g_counters(g_counter(), g_counter()) :: g_counter()
  defp merge_g_counters(local, remote) do
    Map.merge(local, remote, fn _node_id, l_val, r_val -> max(l_val, r_val) end)
  end

  @spec validate_amount!(term(), atom()) :: :ok
  defp validate_amount!(amount, _op) when is_integer(amount) and amount > 0, do: :ok

  defp validate_amount!(amount, op) do
    raise ArgumentError,
          "amount for #{op} must be a positive integer, got: #{inspect(amount)}"
  end
end
```

## New specification

# Design Brief: `TwoPhaseSet` — a CRDT-backed Two-Phase Set

## Problem & Constraints

We need a data structure for eventually-consistent distributed systems: a Two-Phase Set (2P-Set) with CRDT-style merge semantics. Deliver it as an Elixir GenServer module called `TwoPhaseSet`.

The defining constraint of a 2P-Set is that removal is permanent — an element can only ever be removed once, and after removal it can never be re-added. This is the trade-off that makes the 2P-Set simple and correct without requiring causal metadata.

Internally, the state must maintain two `MapSet`s: one for all elements ever added, and one for all elements ever removed. For example, after `add(s, :x)` and `remove(s, :x)`, the state should be `%{added: MapSet.new([:x]), removed: MapSet.new([:x])}` and `:x` is no longer a member.

Additional constraints:
- Deliver the complete module in a single file.
- Use only the OTP standard library — no external dependencies.

## Required Interface

Provide the following public API functions:

1. `TwoPhaseSet.start_link(opts)` — starts the process. It should accept a `:name` option for process registration.

2. `TwoPhaseSet.add(server, element)` — adds an element to the set. If the element has previously been removed, raise an `ArgumentError` — once removed from a 2P-Set, an element can never be re-added. If the element is already in the set, this is a no-op. Returns `:ok`.

3. `TwoPhaseSet.remove(server, element)` — removes an element from the set. The element must currently be in the set (i.e., it must have been added and not yet removed); otherwise, raise an `ArgumentError`. Returns `:ok`.

4. `TwoPhaseSet.member?(server, element)` — returns `true` if the element is currently in the set, `false` otherwise. An element is present if it is in the add-set but not in the remove-set.

5. `TwoPhaseSet.members(server)` — returns a `MapSet` of all elements currently in the set (elements in the add-set minus elements in the remove-set).

6. `TwoPhaseSet.merge(server, remote_state)` — merges a remote 2P-Set state into the local one. The merge computes the union of the local and remote add-sets, and separately the union of the local and remote remove-sets. Returns `:ok`.

7. `TwoPhaseSet.state(server)` — returns the raw internal state of the set so it can be sent to another node for merging. Return it as a map with two keys: `:added` (a `MapSet` of all elements ever added) and `:removed` (a `MapSet` of all elements that have been removed — the "tombstone" set).

## Acceptance Criteria

- The merge operation must be idempotent (merging the same state twice gives the same result), commutative (merging A into B gives the same value as merging B into A), and associative. These properties are what make it a valid CRDT.
- `add/2` raises `ArgumentError` on an element that was previously removed, is a no-op when the element is already in the set, and otherwise returns `:ok`.
- `remove/2` raises `ArgumentError` unless the element is currently in the set, and otherwise returns `:ok`.
- `member?/2` reflects presence as "in the add-set but not in the remove-set."
- `members/1` yields the add-set minus the remove-set as a `MapSet`.
- `state/1` exposes the internal state as `%{added: ..., removed: ...}` with `MapSet` values, suitable for transmission to another node.
- The module is self-contained in one file and depends only on the OTP standard library.
