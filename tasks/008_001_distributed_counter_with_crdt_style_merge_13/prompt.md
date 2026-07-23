# Implement the missing function

Below is the complete specification of a task, followed by a working,
fully tested module that solves it — except that `empty_state` has been
removed: every clause body is blanked to `# TODO`. Implement exactly that
function so the whole module passes the task's full test suite again.
Change nothing else — every other function, attribute, and clause must
stay exactly as shown.

## The task

# PN-Counter GenServer Specification

## Overview

This document specifies an Elixir GenServer module named `Counter` that maintains a PN-Counter (positive-negative counter) with CRDT-style merge semantics, suitable for eventually-consistent distributed systems.

The module's internal state tracks, for each node_id, the total accumulated increments and total accumulated decrements as two separate maps. A node appears in the `:p` map only once it has been incremented, and appears in the `:n` map only once it has been decremented — a node with no operation of a given kind is simply absent from that map, so looking it up yields `nil`, not `0`. For example, after `increment(s, :a, 3)` and `decrement(s, :a, 1)`, the state is `%{p: %{a: 3}, n: %{a: 1}}` and the value is `2`.

The complete module must be provided in a single file. It must use only the OTP standard library, with no external dependencies.

## API

The public API consists of the following functions:

- `Counter.start_link(opts)` starts the process. It accepts a `:name` option for process registration.

- `Counter.increment(server, node_id, amount \\ 1)` increments the counter for the given node. Returns `:ok`.

- `Counter.decrement(server, node_id, amount \\ 1)` decrements the counter for the given node. Returns `:ok`.

- `Counter.value(server)` returns the current integer value of the counter. The value is computed as the sum of all increments across all nodes minus the sum of all decrements across all nodes.

- `Counter.merge(server, remote_state)` merges a remote counter state into the local one. For each node_id, the merged result takes the maximum of the local and remote increment counts, and separately the maximum of the local and remote decrement counts. This is the standard PN-Counter merge rule. Returns `:ok`.

- `Counter.state(server)` returns the raw internal state of the counter so it can be sent to another node for merging. It is returned as a map with two keys: `:p` for the positive map (node_id => total increments) and `:n` for the negative map (node_id => total decrements). A fresh counter's state is `%{p: %{}, n: %{}}`.

## Edge cases

Merge must be idempotent (merging the same state twice gives the same result), commutative (merging A into B gives the same value as merging B into A), and associative. These properties are what make it a valid CRDT. A remote state may omit a node from either map; an absent entry is treated as `0` when taking the maximum (so the local count is kept).

Amounts passed to increment and decrement will always be positive integers. If someone tries to pass a non-positive amount, the code must raise an `ArgumentError`.

## The module with `empty_state` missing

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

  defp empty_state do
    # TODO
  end

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

Give me only the complete implementation of `empty_state` (including any
`@doc`/`@spec`/`@impl` lines that belong directly above it) — the
function alone, not the whole module.
