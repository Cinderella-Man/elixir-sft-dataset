Write me an Elixir GenServer module called `LWWSet` that maintains a Last-Writer-Wins Element Set (LWW-Element-Set) with CRDT-style merge semantics, suitable for eventually-consistent distributed systems.

I need these functions in the public API:

- `LWWSet.start_link(opts)` to start the process. It should accept a `:name` option for process registration.

- `LWWSet.add(server, element, timestamp)` which adds an element to the set with the given timestamp. If the element was already added with an earlier timestamp, the timestamp is updated to the newer one. Returns `:ok`.

- `LWWSet.remove(server, element, timestamp)` which marks an element as removed at the given timestamp. Returns `:ok`.

- `LWWSet.member?(server, element)` which returns `true` if the element is currently in the set, `false` otherwise. An element is considered present if its add timestamp is strictly greater than its remove timestamp (or if it has been added but never removed).

- `LWWSet.members(server)` which returns a `MapSet` of all elements currently in the set (i.e., all elements whose add timestamp is strictly greater than their remove timestamp, or who have been added but never removed).

- `LWWSet.merge(server, remote_state)` which merges a remote set state into the local one. For each element, the merged result should take the maximum of the local and remote add timestamps, and separately the maximum of the local and remote remove timestamps. This is the standard LWW-Element-Set merge rule. Returns `:ok`.

- `LWWSet.state(server)` which returns the raw internal state of the set so it can be sent to another node for merging. Return it as a map with two keys: `:adds` for the add map (element => timestamp) and `:removes` for the remove map (element => timestamp).

The internal state should track, for each element, the latest add timestamp and the latest remove timestamp as two separate maps. For example, after `add(s, :x, 10)` and `remove(s, :x, 5)`, the element `:x` is still in the set because `10 > 5`. After `remove(s, :x, 15)`, it would no longer be in the set because `15 > 10`.

Merge must be idempotent (merging the same state twice gives the same result), commutative (merging A into B gives the same value as merging B into A), and associative. These properties are what make it a valid CRDT.

Timestamps must be positive integers. If someone tries to pass a non-positive timestamp, raise an `ArgumentError`.

When add and remove have the exact same timestamp for an element, the element should be considered **not** in the set (remove-wins bias on ties).

Give me the complete module in a single file. Use only OTP standard library, no external dependencies.