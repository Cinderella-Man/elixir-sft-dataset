Write me an Elixir GenServer module called `Counter` that maintains a PN-Counter (positive-negative counter) with CRDT-style merge semantics, suitable for eventually-consistent distributed systems.

I need these functions in the public API:

- `Counter.start_link(opts)` to start the process. It should accept a `:name` option for process registration.

- `Counter.increment(server, node_id, amount \\ 1)` which increments the counter for the given node. Returns `:ok`.

- `Counter.decrement(server, node_id, amount \\ 1)` which decrements the counter for the given node. Returns `:ok`.

- `Counter.value(server)` which returns the current integer value of the counter. The value is computed as the sum of all increments across all nodes minus the sum of all decrements across all nodes.

- `Counter.merge(server, remote_state)` which merges a remote counter state into the local one. For each node_id, the merged result should take the maximum of the local and remote increment counts, and separately the maximum of the local and remote decrement counts. This is the standard PN-Counter merge rule. Returns `:ok`.

- `Counter.state(server)` which returns the raw internal state of the counter so it can be sent to another node for merging. Return it as a map with two keys: `:p` for the positive map (node_id => total increments) and `:n` for the negative map (node_id => total decrements).

The internal state should track, for each node_id, the total accumulated increments and total accumulated decrements as two separate maps. For example, after `increment(s, :a, 3)` and `decrement(s, :a, 1)`, the state should be `%{p: %{a: 3}, n: %{a: 1}}` and the value should be `2`.

Merge must be idempotent (merging the same state twice gives the same result), commutative (merging A into B gives the same value as merging B into A), and associative. These properties are what make it a valid CRDT.

Amounts passed to increment and decrement will always be positive integers. If someone tries to pass a non-positive amount, raise an `ArgumentError`.

Give me the complete module in a single file. Use only OTP standard library, no external dependencies.