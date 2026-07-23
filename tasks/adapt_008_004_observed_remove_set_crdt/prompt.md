# Rework this solution for a changed brief

The module below is a complete, tested solution to a neighboring task. Treat
it as your starting codebase, not as a suggestion — carry over what still
fits and rewrite what the new brief demands. Where old code and the new
specification conflict (module name, public API, behavior, constraints,
output format), the new specification is authoritative. Return the complete
final result.

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

Write me an Elixir GenServer module called `ORSet` that maintains an Observed-Remove Set (OR-Set, also known as Add-Wins Set) with CRDT-style merge semantics, suitable for eventually-consistent distributed systems.

I need these functions in the public API:

- `ORSet.start_link(opts)` to start the process. It should accept a `:name` option for process registration. Returns `{:ok, pid}`.

- `ORSet.add(server, element, node_id)` which adds an element to the set. Each add operation generates a unique tag (a `{node_id, counter}` tuple where counter is a per-node monotonically increasing integer maintained inside the GenServer). The counter comes from the node's entry in the `clock`: the first add for a given node uses counter `1`, the next `2`, and so on, and the clock is updated to that value. The tag is associated with the element in the entries map. Returns `:ok`.

- `ORSet.remove(server, element)` which removes an element from the set. This moves **all current tags** for that element from the entries map into the tombstones set, and the element's key is deleted from the entries map entirely. If the element is not currently in the set, raise an `ArgumentError`. Returns `:ok`.

- `ORSet.member?(server, element)` which returns `true` if the element is currently in the set (has at least one tag not in tombstones), `false` otherwise.

- `ORSet.members(server)` which returns a `MapSet` of all elements currently in the set.

- `ORSet.merge(server, remote_state)` which merges a remote OR-Set state into the local one. `remote_state` is a map with the same three keys returned by `state/1`. For the entries map: for each element, take the union of local and remote tag sets. For the tombstones set: take the union of local and remote tombstones. For the clock: for each node_id, take the maximum of the local and remote counter values (so a later add on that node produces a tag whose counter exceeds any already observed). After merging, any tag present in the tombstones must be removed from the entries; if an element's tag set becomes empty as a result, drop its key from the entries map. Returns `:ok`.

- `ORSet.state(server)` which returns the raw internal state of the set. Return it as a map with three keys: `:entries` (a map of element => `MapSet` of tags), `:tombstones` (a `MapSet` of all tombstoned tags), and `:clock` (a map of node_id => current counter value).

The key property of the OR-Set is that **add wins over concurrent remove**. If node A adds element `:x` (generating a new tag) while node B concurrently removes `:x` (tombstoning only the tags it can see), after merge `:x` is still in the set because node A's new tag is not in B's tombstones. This is what makes the OR-Set more useful than the 2P-Set for most applications.

An element can be removed and re-added any number of times. Each re-add generates a fresh tag, so the new addition is not affected by previous tombstones. Because the counter is drawn from the (merged) clock, a re-add after tombstones have been merged in still produces a tag that is not itself tombstoned.

The internal state should have:
- `entries`: `%{element => MapSet.t({node_id, counter})}` — for each element, the set of active (non-tombstoned) unique tags
- `tombstones`: `MapSet.t({node_id, counter})` — all tags that have been removed
- `clock`: `%{node_id => integer}` — the latest counter value used for each node

Merge must be idempotent, commutative, and associative.

Give me the complete module in a single file. Use only OTP standard library, no external dependencies.
