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
