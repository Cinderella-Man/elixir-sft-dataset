Write me an Elixir GenServer module called `TwoPhaseSet` that maintains a Two-Phase Set (2P-Set) with CRDT-style merge semantics, suitable for eventually-consistent distributed systems.

I need these functions in the public API:

- `TwoPhaseSet.start_link(opts)` to start the process. It should accept a `:name` option for process registration.

- `TwoPhaseSet.add(server, element)` which adds an element to the set. If the element has previously been removed, raise an `ArgumentError` — once removed from a 2P-Set, an element can never be re-added. If the element is already in the set, this is a no-op. Returns `:ok`.

- `TwoPhaseSet.remove(server, element)` which removes an element from the set. The element must currently be in the set (i.e., it must have been added and not yet removed); otherwise, raise an `ArgumentError`. Returns `:ok`.

- `TwoPhaseSet.member?(server, element)` which returns `true` if the element is currently in the set, `false` otherwise. An element is present if it is in the add-set but not in the remove-set.

- `TwoPhaseSet.members(server)` which returns a `MapSet` of all elements currently in the set (elements in the add-set minus elements in the remove-set).

- `TwoPhaseSet.merge(server, remote_state)` which merges a remote 2P-Set state into the local one. The merge computes the union of the local and remote add-sets, and separately the union of the local and remote remove-sets. Returns `:ok`.

- `TwoPhaseSet.state(server)` which returns the raw internal state of the set so it can be sent to another node for merging. Return it as a map with two keys: `:added` (a `MapSet` of all elements ever added) and `:removed` (a `MapSet` of all elements that have been removed — the "tombstone" set).

The internal state should maintain two `MapSet`s: one for all elements ever added, and one for all elements ever removed. For example, after `add(s, :x)` and `remove(s, :x)`, the state should be `%{added: MapSet.new([:x]), removed: MapSet.new([:x])}` and `:x` is no longer a member.

Merge must be idempotent (merging the same state twice gives the same result), commutative (merging A into B gives the same value as merging B into A), and associative. These properties are what make it a valid CRDT.

The key constraint of a 2P-Set is that removal is permanent — an element can only ever be removed once, and after removal it can never be re-added. This is the trade-off that makes the 2P-Set simple and correct without requiring causal metadata.

Give me the complete module in a single file. Use only OTP standard library, no external dependencies.