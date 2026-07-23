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
