# Implement the missing function

Below is the complete specification of a task, followed by a working,
fully tested module that solves it — except that `state` has been
removed: every clause body is blanked to `# TODO`. Implement exactly that
function so the whole module passes the task's full test suite again.
Change nothing else — every other function, attribute, and clause must
stay exactly as shown.

## The task

# LWWSet — Last-Writer-Wins Element Set Specification

## Overview

This document specifies an Elixir GenServer module named `LWWSet` that maintains a Last-Writer-Wins Element Set (LWW-Element-Set) with CRDT-style merge semantics, suitable for eventually-consistent distributed systems.

The module's internal state tracks, for each element, the latest add timestamp and the latest remove timestamp as two separate maps. For example, after `add(s, :x, 10)` and `remove(s, :x, 5)`, the element `:x` is still in the set because `10 > 5`. After `remove(s, :x, 15)`, it would no longer be in the set because `15 > 10`.

Merge must be idempotent (merging the same state twice gives the same result), commutative (merging A into B gives the same value as merging B into A), and associative. These properties are what make it a valid CRDT.

The complete module must be delivered in a single file. It must use only the OTP standard library, with no external dependencies.

## API

The public API consists of the following functions:

- `LWWSet.start_link(opts)` starts the process. It accepts a `:name` option for process registration. It returns `{:ok, pid}`.

- `LWWSet.add(server, element, timestamp)` adds an element to the set with the given timestamp. If the element was already added with an earlier timestamp, the timestamp is updated to the newer one. It returns `:ok`.

- `LWWSet.remove(server, element, timestamp)` marks an element as removed at the given timestamp. It returns `:ok`.

- `LWWSet.member?(server, element)` returns `true` if the element is currently in the set, `false` otherwise. An element is considered present if its add timestamp is strictly greater than its remove timestamp (or if it has been added but never removed).

- `LWWSet.members(server)` returns a `MapSet` of all elements currently in the set (i.e., all elements whose add timestamp is strictly greater than their remove timestamp, or who have been added but never removed).

- `LWWSet.merge(server, remote_state)` merges a remote set state into the local one. `remote_state` has the same shape returned by `LWWSet.state/1` (a map with `:adds` and `:removes` keys), and either map may omit elements. For each element, the merged result takes the maximum of the local and remote add timestamps, and separately the maximum of the local and remote remove timestamps. This is the standard LWW-Element-Set merge rule. It returns `:ok`.

- `LWWSet.state(server)` returns the raw internal state of the set so it can be sent to another node for merging. It is returned as a map with two keys: `:adds` for the add map (element => timestamp) and `:removes` for the remove map (element => timestamp). An element appears in a given map only if the corresponding operation was applied to it, so looking up an element that was never added returns `nil` in `:adds`, and one that was never removed returns `nil` in `:removes`. The state of a fresh set is `%{adds: %{}, removes: %{}}`.

## Edge cases

- Timestamps must be positive integers. If someone tries to pass a non-positive timestamp, the function must raise an `ArgumentError`.

- When add and remove have the exact same timestamp for an element, the element must be considered **not** in the set (remove-wins bias on ties).

## The module with `state` missing

```elixir
defmodule LWWSet do
  @moduledoc """
  A GenServer implementing a Last-Writer-Wins Element Set (LWW-Element-Set) CRDT.

  ## Overview

  An LWW-Element-Set is a Conflict-free Replicated Data Type (CRDT) that supports
  both add and remove operations on set elements in distributed systems where nodes
  may not be in constant communication.

  It works by maintaining two maps:
    - `adds`    — maps each element to the latest timestamp at which it was added
    - `removes` — maps each element to the latest timestamp at which it was removed

  An element is considered present in the set if its add timestamp is strictly
  greater than its remove timestamp (or if it has never been removed). On ties,
  the remove wins (remove-bias).

  ## CRDT Merge Semantics

  Merging two LWW-Element-Set states is performed by taking the **per-element
  maximum** of each timestamp map independently:

      merged.adds[elem]    = max(local.adds[elem],    remote.adds[elem])
      merged.removes[elem] = max(local.removes[elem], remote.removes[elem])

  This merge function is:
    - **Idempotent**: `merge(s, s) == s`
    - **Commutative**: `merge(a, b) == merge(b, a)`
    - **Associative**: `merge(merge(a, b), c) == merge(a, merge(b, c))`

  ## Example

      {:ok, s} = LWWSet.start_link([])

      LWWSet.add(s, :alice, 1)
      LWWSet.add(s, :bob, 2)
      LWWSet.remove(s, :alice, 3)

      LWWSet.members(s)
      #=> MapSet.new([:bob])

      remote = %{adds: %{charlie: 5}, removes: %{}}
      LWWSet.merge(s, remote)

      LWWSet.members(s)
      #=> MapSet.new([:bob, :charlie])
  """

  use GenServer

  @type element :: term()
  @type timestamp :: pos_integer()
  @type ts_map :: %{optional(element()) => pos_integer()}
  @type lww_state :: %{adds: ts_map(), removes: ts_map()}
  @type server :: GenServer.server()

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  @doc """
  Starts the LWWSet process.

  ## Options

    * `:name` — optional name for process registration, passed directly to
      `GenServer.start_link/3`. Accepts any valid `GenServer` name term
      (atom, `{:global, term}`, `{:via, module, term}`, etc.).

  ## Examples

      # Anonymous process
      {:ok, pid} = LWWSet.start_link([])

      # Named process
      {:ok, _} = LWWSet.start_link(name: MySet)
      LWWSet.members(MySet)
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    {name_opts, _rest} = Keyword.split(opts, [:name])
    GenServer.start_link(__MODULE__, :ok, name_opts)
  end

  @doc """
  Adds `element` to the set with the given `timestamp`.

  If the element already has a recorded add timestamp, the new timestamp
  is kept only if it is greater than the existing one (max wins).

  `timestamp` must be a positive integer; raises `ArgumentError` otherwise.

  Returns `:ok`.
  """
  @spec add(server(), element(), timestamp()) :: :ok
  def add(server, element, timestamp) do
    validate_timestamp!(timestamp, :add)
    GenServer.call(server, {:add, element, timestamp})
  end

  @doc """
  Marks `element` as removed at the given `timestamp`.

  If the element already has a recorded remove timestamp, the new timestamp
  is kept only if it is greater than the existing one (max wins).

  `timestamp` must be a positive integer; raises `ArgumentError` otherwise.

  Returns `:ok`.
  """
  @spec remove(server(), element(), timestamp()) :: :ok
  def remove(server, element, timestamp) do
    validate_timestamp!(timestamp, :remove)
    GenServer.call(server, {:remove, element, timestamp})
  end

  @doc """
  Returns `true` if `element` is currently in the set, `false` otherwise.

  An element is present when its add timestamp is strictly greater than its
  remove timestamp. If the timestamps are equal (tie), the element is
  considered absent (remove-wins bias).
  """
  @spec member?(server(), element()) :: boolean()
  def member?(server, element) do
    GenServer.call(server, {:member?, element})
  end

  @doc """
  Returns a `MapSet` of all elements currently in the set.

  An element is included when its add timestamp is strictly greater than its
  remove timestamp (or it has never been removed).
  """
  @spec members(server()) :: MapSet.t()
  def members(server) do
    GenServer.call(server, :members)
  end

  @doc """
  Merges a remote LWW-Element-Set state into the local state.

  `remote_state` must be a map of the form `%{adds: %{...}, removes: %{...}}`
  — i.e. the structure returned by `LWWSet.state/1`.

  For each element, the merge takes the **maximum** of the local and remote
  timestamps for both `adds` and `removes` independently. This ensures the
  merge is idempotent, commutative, and associative.

  Returns `:ok`.
  """
  @spec merge(server(), lww_state()) :: :ok
  def merge(server, %{adds: adds, removes: removes} = _remote_state)
      when is_map(adds) and is_map(removes) do
    GenServer.call(server, {:merge, %{adds: adds, removes: removes}})
  end

  def merge(_server, invalid) do
    raise ArgumentError,
          "remote_state must be a map with :adds and :removes keys, got: #{inspect(invalid)}"
  end

  def state(server) do
    # TODO
  end

  # ---------------------------------------------------------------------------
  # GenServer callbacks
  # ---------------------------------------------------------------------------

  @impl GenServer
  def init(:ok) do
    {:ok, empty_state()}
  end

  @impl GenServer
  def handle_call({:add, element, timestamp}, _from, state) do
    new_state =
      update_in(state, [:adds, element], fn
        nil -> timestamp
        current -> max(current, timestamp)
      end)

    {:reply, :ok, new_state}
  end

  def handle_call({:remove, element, timestamp}, _from, state) do
    new_state =
      update_in(state, [:removes, element], fn
        nil -> timestamp
        current -> max(current, timestamp)
      end)

    {:reply, :ok, new_state}
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

  @spec empty_state() :: lww_state()
  defp empty_state, do: %{adds: %{}, removes: %{}}

  @spec element_present?(lww_state(), element()) :: boolean()
  defp element_present?(%{adds: adds, removes: removes}, element) do
    case Map.fetch(adds, element) do
      {:ok, add_ts} ->
        remove_ts = Map.get(removes, element, 0)
        add_ts > remove_ts

      :error ->
        false
    end
  end

  @spec compute_members(lww_state()) :: MapSet.t()
  defp compute_members(%{adds: adds, removes: removes}) do
    adds
    |> Enum.filter(fn {element, add_ts} ->
      remove_ts = Map.get(removes, element, 0)
      add_ts > remove_ts
    end)
    |> Enum.map(fn {element, _ts} -> element end)
    |> MapSet.new()
  end

  @spec merge_states(lww_state(), lww_state()) :: lww_state()
  defp merge_states(%{adds: la, removes: lr}, %{adds: ra, removes: rr}) do
    %{
      adds: merge_ts_maps(la, ra),
      removes: merge_ts_maps(lr, rr)
    }
  end

  # Merges two timestamp maps by taking the per-element maximum.
  @spec merge_ts_maps(ts_map(), ts_map()) :: ts_map()
  defp merge_ts_maps(local, remote) do
    Map.merge(local, remote, fn _element, l_ts, r_ts -> max(l_ts, r_ts) end)
  end

  @spec validate_timestamp!(term(), atom()) :: :ok
  defp validate_timestamp!(ts, _op) when is_integer(ts) and ts > 0, do: :ok

  defp validate_timestamp!(ts, op) do
    raise ArgumentError,
          "timestamp for #{op} must be a positive integer, got: #{inspect(ts)}"
  end
end
```

Give me only the complete implementation of `state` (including any
`@doc`/`@spec`/`@impl` lines that belong directly above it) — the
function alone, not the whole module.
