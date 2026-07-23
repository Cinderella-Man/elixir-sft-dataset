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
